# Security

## Principles

1. **No secrets in git** – real config is gitignored; only `MigrationConfig.example.psd1` is committed.  
2. **Strong temporary passwords** – `New-StrongPassword` uses `RNGCryptoServiceProvider`; never log or write the clear text.  
3. **Least residual footprint** – Phase 4 removes temp admin, tasks, RunOnce, and working directory.  
4. **Verify cloud state** – BitLocker keys and Intune enrollment must be confirmed in admin centers, not only from local exit codes.

## Temporary local admin

- Default name: `MigrationInProgress` (override with `TempUser` in config).  
- Created or password-reset during `Start-DeviceMigration`.  
- Password is a `SecureString` only in memory for the `New-LocalUser` / `Set-LocalUser` call.  
- Removed in Phase 4 / `Remove-MigrationArtifacts`.  
- Prefer **Windows LAPS** for any standing local admin after migration.

## BitLocker

- Escrow uses the supported `BackupToAAD-BitLockerKeyProtector` path.  
- Policy mismatches can produce warnings even when the attempt was made—**always verify** in Entra ID → Devices → BitLocker keys (or Intune).  
- Do not store recovery passwords in logs or migration folders.

## Provisioning packages

- PPKGs can contain sensitive join material. Protect the file path with ACLs appropriate for SYSTEM read during Phase 1.  
- Do not commit `.ppkg` files to this repository.

## Logging

- Transcripts under `C:\Logs\Transcript` may contain host output; treat log shares as sensitive.  
- Avoid embedding PATs or passwords in scripts (the original toolkit’s GitHub log-upload pattern was intentionally **not** carried forward).

## Registry / legal notice

Phase 2 sets a temporary legal notice so users know to sign in with work accounts. Phase 4 clears:

- `legalnoticecaption` / `legalnoticetext`  
- `dontdisplaylastusername`  
- migration lock-screen image policy  
- AutoAdminLogon related to the temp user

## Scheduled tasks

Tasks under `\DMU\` run as **SYSTEM**. Only stage scripts you trust. Remove them promptly after migration.

## Hardening checklist

- [ ] `MigrationConfig.psd1` not in source control  
- [ ] PPKG stored on a controlled path  
- [ ] BitLocker key visible in Entra after Phase 2  
- [ ] Temp local admin removed after Phase 4  
- [ ] `\DMU\` and `\AAD Migration\` task folders empty/removed  
- [ ] LAPS or equivalent for ongoing local admin  
- [ ] User has signed in and OneDrive/KFM is healthy  
