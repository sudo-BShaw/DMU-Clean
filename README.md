# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration), this edition focuses on:

- **Security first** – no hardcoded secrets or weak passwords
- **Modular design** – small, testable functions instead of monolithic scripts
- **Reduced duplication** – shared logging, bootstrap, and error handling
- **Clear configuration** – example-only config files
- **Maintainability** – consistent naming, modern PowerShell practices, and documentation

> **Status**: Early refactor / work-in-progress. Core structure, security fixes, and the main orchestrator are in place. Phase scripts are the next focus.

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
│   ├── DMU.psd1                   # Module manifest (v0.2.0)
│   ├── DMU.psm1                   # Root module
│   ├── Public/                    # Exported functions
│   │   ├── Start-DeviceMigration.ps1   ← main orchestrator
│   │   ├── Get-DeviceJoinStatus.ps1
│   │   └── Remove-MigrationArtifacts.ps1
│   ├── Private/                   # Internal helpers
│   │   ├── Initialize-Logging.ps1
│   │   └── New-StrongPassword.ps1
│   └── Scripts/                   # Phase scripts (next)
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
# Edit TenantID, ProvisioningPack path, etc.

# Run (elevates automatically if needed)
.\Setup.ps1

# Or with options
.\Setup.ps1 -ForceCleanup
.\Setup.ps1 -SkipStatusCheck
```

You can also call the orchestrator directly after loading the functions:

```powershell
Start-DeviceMigration -ForceCleanup
```

## What `Start-DeviceMigration` currently does

1. Loads and validates configuration (refuses placeholder TenantID)
2. Initializes consistent logging (transcript + optional PSFramework)
3. Optionally removes previous migration artifacts
4. Checks device join / Intune enrollment status via `dsregcmd`
5. Creates required working directories
6. Creates / resets the temporary local admin account with a **cryptographically strong random password** (never logged or written to disk in clear text)
7. Validates the provisioning package path
8. Prints the high-level phase plan (scaffolding for upcoming phase scripts)
9. Returns a summary object and cleans up logging

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
- GitHub PATs (if used later) should live outside the repo and have minimal scopes.

## Roadmap

- [x] New repository + clean structure
- [x] Example configuration (no secrets)
- [x] Shared logging bootstrap
- [x] Clean `Get-DeviceJoinStatus`
- [x] Thin `Setup.ps1`
- [x] Modular `Start-DeviceMigration` orchestrator
- [x] Random strong temp password (`New-StrongPassword`)
- [ ] Phase scripts (`Phase1-EntraJoin`, BitLocker escrow, OneDrive, cleanup)
- [ ] Scheduled-task / RunOnce helpers
- [ ] Pester tests for core functions
- [ ] Full documentation in `docs/`

## Credits

- Original concept and extensive real-world logic: [aollivierre](https://github.com/aollivierre)
- Inspiration from community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT

---

**This is a community-driven clean refactor.** Contributions, issues, and testing feedback are welcome.
