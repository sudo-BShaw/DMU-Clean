# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration), this edition focuses on:

- **Security first** – no hardcoded secrets or weak passwords
- **Modular design** – small, testable functions instead of monolithic scripts
- **Reduced duplication** – shared logging, bootstrap, and error handling
- **Clear configuration** – example-only config files
- **Maintainability** – consistent naming, modern PowerShell practices, and documentation

> **Status**: Active development. Core orchestrator + Phase 1 (Entra Join) are implemented.

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
├── Setup.ps1                      # Thin entry point → Start-DeviceMigration
├── config/
│   └── MigrationConfig.example.psd1
├── src/
│   ├── DMU.psd1 / DMU.psm1
│   ├── Public/
│   │   ├── Start-DeviceMigration.ps1
│   │   ├── Get-DeviceJoinStatus.ps1
│   │   └── Remove-MigrationArtifacts.ps1
│   ├── Private/
│   │   ├── Initialize-Logging.ps1
│   │   └── New-StrongPassword.ps1
│   └── Scripts/
│       └── Phase1-EntraJoin.ps1   ← PPKG + RunOnce hand-off
├── tests/
└── docs/
```

## Quick Start

```powershell
# Clone
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

# Copy and edit configuration (NEVER commit real secrets)
Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID and ProvisioningPack path

# Prepare only (stage scripts, create temp user, etc.)
.\Setup.ps1 -ForceCleanup

# Prepare + immediately run Phase 1 (apply PPKG, register Phase 2, reboot)
.\Setup.ps1 -ForceCleanup -LaunchPhase1

# Same but skip the automatic reboot
.\Setup.ps1 -LaunchPhase1 -SkipReboot
```

## Phase 1 – Entra Join (`src/Scripts/Phase1-EntraJoin.ps1`)

| Step | Action |
|------|--------|
| 1 | Load config & initialize logging |
| 2 | Validate the provisioning package (PPKG) exists |
| 3 | Optionally set a "Migration in Progress" wallpaper / lock screen |
| 4 | Apply the PPKG via `Install-ProvisioningPackage` (or `provtool.exe` fallback) |
| 5 | Register Phase 2 via `HKLM\...\RunOnce` |
| 6 | Copy Phase 2 script into the migration working directory |
| 7 | Reboot (unless `-SkipReboot`) so Entra Join can complete and Phase 2 runs |

You can also run Phase 1 directly after staging:

```powershell
& 'C:\ProgramData\AADMigration\Scripts\Phase1-EntraJoin.ps1' `
    -ConfigPath 'C:\ProgramData\AADMigration\MigrationConfig.psd1'
```

## What `Start-DeviceMigration` does

1. Loads and validates configuration (refuses placeholder TenantID)
2. Initializes consistent logging
3. Optionally removes previous migration artifacts (`-ForceCleanup`)
4. Checks device join / Intune enrollment status
5. Creates required working directories
6. Creates / resets the temporary local admin with a **strong random password**
7. Validates the provisioning package path
8. **Stages** all `Phase*.ps1` scripts + config into `C:\ProgramData\AADMigration`
9. Optionally launches Phase 1 (`-LaunchPhase1`)

## Prerequisites

- Windows 10 / 11 (not Server)
- PowerShell 5.1
- Administrative rights
- Entra ID P1 + Intune P1 (for automatic enrollment)
- A properly configured Windows Provisioning Package (PPKG)
- Network access to required endpoints

## Security Notes

- **Never** commit real TenantIDs, PATs, or passwords.
- Temporary local accounts receive a strong random password generated at runtime.
- Prefer Windows LAPS for ongoing local admin password management.

## Roadmap

- [x] New repository + clean structure
- [x] Example configuration (no secrets)
- [x] Shared logging bootstrap
- [x] Clean `Get-DeviceJoinStatus`
- [x] Thin `Setup.ps1`
- [x] Modular `Start-DeviceMigration` orchestrator
- [x] Random strong temp password (`New-StrongPassword`)
- [x] **Phase1-EntraJoin** (PPKG + RunOnce)
- [ ] Phase2-EscrowBitlocker
- [ ] Phase3-OneDrive helpers
- [ ] Phase4-Cleanup
- [ ] Scheduled-task helpers
- [ ] Pester tests
- [ ] Full documentation in `docs/`

## Credits

- Original concept and extensive real-world logic: [aollivierre](https://github.com/aollivierre)
- Inspiration from community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT

---

**This is a community-driven clean refactor.** Contributions, issues, and testing feedback are welcome.
