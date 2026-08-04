# Configuration

Configuration is a PowerShell data file (`.psd1`) imported with `Import-PowerShellDataFile`.

## Files

| File | Purpose |
|------|---------|
| `config/MigrationConfig.example.psd1` | Safe template committed to git |
| `config/MigrationConfig.psd1` | **Real** values – local only, gitignored |
| `C:\ProgramData\AADMigration\MigrationConfig.psd1` | Staged copy used by phase scripts |

## Keys

| Key | Type | Default / example | Notes |
|-----|------|-------------------|-------|
| `TenantID` | string (GUID) | placeholder zeros | **Required.** Orchestrator throws if missing or still placeholder |
| `MigrationPath` | string | `C:\ProgramData\AADMigration` | Staging root for scripts/config |
| `LogsPath` | string | `C:\Logs` | Transcript + optional PSF logs |
| `JobName` | string | `AAD_Migration` | Used in log file names |
| `TempUser` | string | `MigrationInProgress` | Temporary local admin created for the migration window |
| `UseOneDriveKFM` | bool | `$true` | Phase 3 writes KFM policy when `$true` |
| `InstallOneDrive` | bool | `$true` | Phase 3 warns if client missing when `$true` |
| `ProvisioningPack` | string | path to `.ppkg` | Absolute or relative to `MigrationPath` |
| `ProvisioningPackName` | string | optional display name | Informational |

## Example

```powershell
@{
    TenantID            = '12345678-1234-1234-1234-123456789abc'
    MigrationPath       = 'C:\ProgramData\AADMigration'
    LogsPath            = 'C:\Logs'
    JobName             = 'AAD_Migration'
    TempUser            = 'MigrationInProgress'
    UseOneDriveKFM      = $true
    InstallOneDrive     = $true
    ProvisioningPack    = 'C:\Packages\Contoso-EntraJoin.ppkg'
    ProvisioningPackName = 'Contoso Entra Join'
}
```

## Validation rules

`Start-DeviceMigration` will **refuse to continue** when:

- The config file path does not exist
- `TenantID` is empty or equal to `00000000-0000-0000-0000-000000000000`

Phase 1 will **fail** if the PPKG path is missing or the file is not on disk.

## Creating a PPKG

Use the Windows Configuration Designer (ICD) or your existing enterprise process to build a package that:

- Joins the device to **Microsoft Entra ID** (not hybrid, unless that is intentional)
- Targets the correct tenant
- Optionally sets device name / local admin policies per your standards

Place the resulting `.ppkg` on a path readable by SYSTEM during Phase 1 and set `ProvisioningPack` accordingly.
