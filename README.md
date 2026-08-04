# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration), this edition focuses on:

- **Security first** – no hardcoded secrets or weak passwords
- **Modular design** – small, testable functions instead of monolithic scripts
- **Reduced duplication** – shared logging, bootstrap, and error handling
- **Clear configuration** – example-only config files
- **Maintainability** – consistent naming, modern PowerShell practices, and documentation

> **Status**: Early refactor / work-in-progress. Core structure and high-priority security/maintainability fixes are in place. Full feature parity with the original is being migrated incrementally.

## Key Improvements Over Original

| Area | Original | This Edition |
|------|----------|--------------|
| Secrets | Hardcoded TenantID + weak `Default1234` password | Example config only; random strong temp password generated at runtime |
| Structure | Large monolithic scripts + Archive bloat | Modular `src/` layout with Public/Private functions |
| Logging | Duplicated bootstrap in every script | Single shared `Initialize-Logging` + consistent helpers |
| Variables | Mixed `$Mode` / `$global:mode`, casing issues | Consistent `$script:` / `$global:` usage and naming |
| Entry point | Heavy Setup.ps1 that re-downloads everything | Thin, cache-aware entry point |
| Documentation | Duplicate README files | Single clear README + docs/ |

## Architecture (Target)

```
DMU-Clean/
├── README.md
├── LICENSE
├── Setup.ps1                      # Thin entry point
├── config/
│   └── MigrationConfig.example.psd1
├── src/
│   ├── DMU.psd1                   # Module manifest
│   ├── DMU.psm1                   # Root module
│   ├── Public/                    # Exported functions
│   │   ├── Start-DeviceMigration.ps1
│   │   ├── Get-DeviceJoinStatus.ps1
│   │   ├── Remove-MigrationArtifacts.ps1
│   │   └── ...
│   ├── Private/                   # Internal helpers
│   │   ├── Initialize-Logging.ps1
│   │   ├── Invoke-ModuleBootstrap.ps1
│   │   ├── New-TemporaryMigrationUser.ps1
│   │   └── ...
│   └── Scripts/                   # Phase / scheduled-task scripts
│       ├── Phase1-EntraJoin.ps1
│       ├── Phase2-EscrowBitlocker.ps1
│       └── ...
├── assets/                        # Icons, banners, ServiceUI (if needed)
├── tests/                         # Pester tests
└── docs/                          # Detailed guides
```

## Quick Start (Current State)

```powershell
# Clone
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

# Copy and edit configuration (NEVER commit real secrets)
Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID, paths, etc.

# Run the cleaned entry point (work in progress)
.\Setup.ps1
```

## Prerequisites

- Windows 10 / 11 (not Server)
- PowerShell 5.1 (required for many Microsoft modules)
- Administrative rights
- Entra ID P1 + Intune P1 (for automatic enrollment)
- A properly configured Windows Provisioning Package (PPKG) created with Windows Configuration Designer
- Network access to required endpoints

## Security Notes

- **Never** commit real TenantIDs, PATs, or passwords.
- Temporary local accounts now receive a cryptographically strong random password.
- Prefer Windows LAPS for ongoing local admin password management.
- GitHub PATs (if used for private PPKG or log upload) should be stored outside the repo and have minimal scopes.

## Roadmap

- [x] New repository + clean structure
- [x] Example configuration (no secrets)
- [x] Shared logging bootstrap
- [x] Clean `Get-DeviceJoinStatus`
- [ ] Thin `Setup.ps1` with caching
- [ ] Modular `Start-DeviceMigration`
- [ ] Phase scripts refactored
- [ ] Random temp password + LAPS guidance
- [ ] Pester tests for core functions
- [ ] Full documentation in `docs/`

## Credits

- Original concept and extensive real-world logic: [aollivierre](https://github.com/aollivierre)
- Inspiration from community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT (same spirit as the original project)

---

**This is a community-driven clean refactor.** Contributions, issues, and testing feedback are welcome.
