# Testing

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+ for the runner  
- **Pester 5+** (`Run-Tests.ps1` will install for CurrentUser if missing)

## Run the suite

```powershell
cd <repo-root>
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Detailed
```

Results: `tests/TestResults.xml` (NUnit format, gitignored).

## Layout

| File | Focus |
|------|--------|
| `Helpers.ps1` | Dot-sources Public + Private |
| `New-StrongPassword.Tests.ps1` | Length, SecureString, uniqueness |
| `Get-DeviceJoinStatus.Tests.ps1` | Object shape + NeedsMigration matrix |
| `Get-OneDriveSyncStatus.Tests.ps1` | Property surface, UserProfile |
| `Enable-OneDriveKFM.Tests.ps1` | Parameters, WhatIf |
| `Invoke-BitLockerEscrow.Tests.ps1` | Parameters; WhatIf when cmdlets exist |
| `Remove-MigrationArtifacts.Tests.ps1` | Isolated `$TestDrive` cleanup |
| `Start-DeviceMigration.Tests.ps1` | Missing config / placeholder TenantID |
| `ScheduledTask.Tests.ps1` | Helper parameter surface, WhatIf |

## Design notes

- Tests **avoid** destructive actions on the real machine: they use `-WhatIf`, `$TestDrive`, and decision-matrix unit checks.  
- BitLocker tests are skipped when `Get-BitLockerVolume` is not present.  
- Live `dsregcmd` output varies by machine; join-status tests assert structure and pure logic, not a fixed join type.

## Adding tests

1. Create `tests/<Name>.Tests.ps1`.  
2. `BeforeAll { . (Join-Path $PSScriptRoot 'Helpers.ps1') }`.  
3. Prefer `Should -Throw` / `Should -Not -Throw` and property assertions.  
4. Re-run `.\tests\Run-Tests.ps1`.
