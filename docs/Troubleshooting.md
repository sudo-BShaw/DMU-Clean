# Troubleshooting

## Orchestrator refuses to start

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Config file not found | No `MigrationConfig.psd1` | Copy from example and edit |
| TenantID placeholder error | Still `00000000-...` | Set real tenant GUID |
| Not PowerShell 5.1 | Running under 7 only | Use `powershell.exe` 5.1 for Setup |
| Access denied | Not elevated | Let Setup relaunch elevated, or Run as admin |

## Phase 1 – PPKG / join

| Symptom | Action |
|---------|--------|
| PPKG not found | Fix `ProvisioningPack` path; ensure SYSTEM can read the file |
| `Install-ProvisioningPackage` missing | Confirm Windows client OS; fallback uses `provtool.exe` |
| Device still Workgroup after reboot | Check PPKG contents, network, Entra join logs (`dsregcmd /status`, Event Viewer) |
| Hybrid instead of pure Entra | PPKG or domain policy still domain-joining; adjust package |

```powershell
Get-DeviceJoinStatus | Format-List
dsregcmd /status
```

## Phase 2 – BitLocker

| Symptom | Action |
|---------|--------|
| “BitLocker cmdlets not available” | Client OS with BitLocker feature; admin session |
| Escrow warning / policy mismatch | Verify key in Entra admin center anyway; check BitLocker escrow policies |
| No RecoveryPassword protector | Re-run with `-CreateProtectorIfMissing` or enable BitLocker first |

## Phase 3 – OneDrive

| Symptom | Action |
|---------|--------|
| Client not installed | Deploy OneDrive via Intune; `InstallOneDrive` only warns |
| No user folder under SYSTEM | Expected until interactive user sign-in; rely on safety-net copy path when profile detected |
| KFM not moving folders | Confirm tenant allows KFM; user must sign in; Intune OneDrive policies may override registry |

## Phase 4 – Cleanup

| Symptom | Action |
|---------|--------|
| Temp user in use | Log off sessions for that account, re-run Phase 4 |
| Cannot delete MigrationPath | File in use; reboot and re-run with `-PreserveMigrationPath:$false` |
| Tasks remain | `Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder` |

## Scheduled tasks

```powershell
Get-DMUScheduledTask | Format-List
Get-ScheduledTask -TaskPath '\DMU\' | Get-ScheduledTaskInfo
```

- **LastTaskResult** non-zero → open the phase transcript under `C:\Logs\Transcript`.  
- Task never runs → confirm trigger (AtStartup vs OnDemand) and that the machine actually rebooted.

## Logging locations

| Path | Content |
|------|---------|
| `C:\Logs\Transcript\` | Start-Transcript output |
| `C:\Logs\PSF\` | PSFramework CSV (if module present) |
| `C:\ProgramData\AADMigration\Logs\` | Optional staged logs |

## Safe recovery pattern

```powershell
# 1. Status
Get-DeviceJoinStatus

# 2. If join incomplete – fix PPKG / network, re-run Phase 1 with -SkipReboot for testing

# 3. If join OK but keys missing – Phase 2 only
& '...\Phase2-EscrowBitlocker.ps1' -SkipReboot

# 4. If finished – force cleanup
& '...\Phase4-Cleanup.ps1' -SkipReboot
Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder
```
