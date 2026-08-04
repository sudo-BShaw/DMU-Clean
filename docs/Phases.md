# Migration Phases

All phase scripts live under `src/Scripts/` and are copied to `C:\ProgramData\AADMigration\Scripts\` by the orchestrator.

Common parameters on most phases:

| Parameter | Meaning |
|-----------|---------|
| `-ConfigPath` | Path to staged or repo config |
| `-SkipReboot` | Do not call `shutdown /r` at the end |
| `-WhatIf` | Supported where `SupportsShouldProcess` is used |

---

## Phase 1 – Entra Join

**Script:** `Phase1-EntraJoin.ps1`

1. Load config and logging  
2. Validate `ProvisioningPack` exists  
3. Optionally set migration wallpaper / lock-screen image  
4. Install PPKG via `Install-ProvisioningPackage` (fallback: `provtool.exe`)  
5. Register Phase 2 in `HKLM\...\RunOnce`  
6. Copy Phase 2 script into the migration Scripts folder  
7. Reboot after ~30 seconds (unless `-SkipReboot`)

**Requires:** admin / SYSTEM, valid PPKG, network to Entra during/after reboot.

---

## Phase 2 – BitLocker escrow

**Script:** `Phase2-EscrowBitlocker.ps1`  
**Helper:** `Invoke-BitLockerEscrow`

1. Escrow RecoveryPassword protectors with `BackupToAAD-BitLockerKeyProtector`  
2. Optionally create a RecoveryPassword protector if none exist (`-CreateProtectorIfMissing`)  
3. Apply post-join registry (disable AutoAdminLogon, legal notice, hide last username)  
4. Register Phase 3 via RunOnce (or cleanup fallback)  
5. Reboot after ~45 seconds

**Important:** Always confirm the recovery key in the Entra ID / Intune admin center. Cmdlet success does not guarantee the key is visible yet when policies differ.

Drives with BitLocker off are skipped (not treated as fatal).

---

## Phase 3 – OneDrive

**Script:** `Phase3-OneDrive.ps1`  
**Helpers:** `Enable-OneDriveKFM`, `Get-OneDriveSyncStatus`

1. Write KFM silent-opt-in policy under `HKLM\SOFTWARE\Policies\Microsoft\OneDrive` when `UseOneDriveKFM` is true  
2. Start `OneDrive.exe` if installed but not running  
3. Report install / running / folder / KFM hints  
4. Safety-net `robocopy` of Desktop, Documents, Pictures, Downloads → `OneDrive\DMU-Backup`  
5. Register Phase 4 via RunOnce  
6. Reboot after ~60 seconds

**Limits:** Full cloud sync still requires the **user** to sign in with their Entra account. Phase 3 prepares policy and a local backup; it does not complete KFM alone under SYSTEM.

Switches: `-SkipKFM`, `-SkipUserFileCopy`, `-SkipReboot`.

---

## Phase 4 – Cleanup

**Script:** `Phase4-Cleanup.ps1`  
**Helper:** `Remove-MigrationArtifacts`

1. Clear `DMU-*` and legacy `NextRun` RunOnce values  
2. Unregister tasks under `\AAD Migration\` (and use scheduled-task helpers for `\DMU\` when available)  
3. Remove temporary local admin  
4. Clear AutoAdminLogon if it pointed at that account  
5. Reset legal notice / lock-screen policy values  
6. Remove `MigrationPath` unless `-PreserveMigrationPath`  
7. Keep `LogsPath` by default (`-PreserveLogs:$false` to delete)  
8. Print final `Get-DeviceJoinStatus`  
9. Optional reboot

After Phase 4 the device should be ready for normal Entra user sign-in.
