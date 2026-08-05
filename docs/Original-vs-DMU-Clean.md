# Original IntuneDeviceMigration vs DMU-Clean

This document explains the steps in the original [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration) project versus what was generated for **DMU-Clean**, and why actions were removed or added.

---

## 1. Overall shape

| Area | Original | DMU-Clean |
|------|----------|-----------|
| Entry | Heavy `Setup.ps1` (often re-fetched/copied the whole toolkit) | Thin `Setup.ps1` → `Start-DeviceMigration` |
| Core logic | Large monolithic `DeviceMigration.ps1` + phase scripts calling opaque `PostRunOnce-*` helpers | Explicit phase scripts + small Public/Private functions |
| Config | Real values (including weak password / TenantID) often in-repo | `MigrationConfig.example.psd1` only; real file gitignored |
| Secrets | Hardcoded / encrypted PAT patterns for GitHub log upload | No PATs, no Graph app, strong random temp password at runtime |
| Hand-off | RunOnce + `\AAD Migration\` scheduled tasks | RunOnce by default + optional `\DMU\` scheduled tasks |
| Docs / tests | Sparse / duplicated READMEs | `docs/` + Pester 5 suite |

---

## 2. Step-by-step comparison

### A. Bootstrap / launch

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Elevate, set execution policy | Same | Still required for SYSTEM/admin work |
| “Module starter” / EnhancedModules / gallery skips | **Removed** | Added complexity and external coupling; phases only need a few local helpers |
| Re-download or expand full repo on every run | **Removed** | Unreliable offline, slow, and mixed “source of truth”; clone once and run locally instead |
| Dot-source many shared scripts | Dot-source `src/Public` + `src/Private` only | Same idea, narrower surface |

**Added:** `Start-DeviceMigration` as a single orchestrator with `-ForceCleanup`, `-LaunchPhase1`, `-SkipReboot`, `-UseScheduledTasks`, `-WhatIf`.

---

### B. Configuration & identity

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Config with real `TenantID` and weak `TempPass` (e.g. `Default1234`) | Example config; **placeholder TenantID rejected** | Security and “never commit secrets” |
| Fixed temp password | **`New-StrongPassword`** (RNG, SecureString) | Removes weak default credentials |
| Mixed `$Mode` / `$global:mode` | Consistent parameters | Maintainability |

**Removed:** Any assumption that secrets live in the repo or that a static temp password is acceptable.

---

### C. Pre-flight status

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| `Check.ps1` / dsregcmd-style checks | **`Get-DeviceJoinStatus` / `Show-DeviceJoinStatus`** | Same need, cleaner object (`JoinType`, `NeedsMigration`) |
| Exit early if already cloud-joined + enrolled | Same in orchestrator | Avoid unnecessary migration |

**Unchanged in intent:** parse `dsregcmd`, decide whether migration is needed.

---

### D. Working directory & temp admin

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| `C:\ProgramData\AADMigration` layout | Same default path | Compatibility with existing ops muscle memory |
| Create local admin for migration window | Same (`TempUser`, default `MigrationInProgress`) | Still useful for interactive/edge cases |
| Weak/fixed password | Strong random password, never logged | Security |

**Removed:** Staging of GitHub secret folders (`*-secrets`, SecurePAT, SecureKey).

---

### E. Phase 1 – Entra Join

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Apply PPKG for Entra join | **Kept** (`Install-ProvisioningPackage` / `provtool` fallback) | Core of the migration |
| Migration-in-progress image | **Kept** (best-effort wallpaper/lock screen) | User communication |
| Call `PostRunOnce-Phase1EntraJoin` from enhanced modules | **Inlined** clear steps in `Phase1-EntraJoin.ps1` | Those helpers weren’t self-contained in-repo; behavior is explicit now |
| Register next phase (RunOnce) | **Kept** | Reliable one-shot hand-off after reboot |

**Not added:** Graph API join (never required; PPKG is the supported offline/online join vehicle).

---

### F. Phase 2 – BitLocker

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Escrow recovery key to Entra (`BackupToAAD-BitLockerKeyProtector` pattern) | **Kept** as `Invoke-BitLockerEscrow` + Phase 2 | Correct device-side escrow; **no Graph app permissions** |
| PR4B-style detection/remediation packaging | **Simplified** to a phase + reusable function | Intune remediation wrapper is optional packaging, not core logic |
| Legal notice / disable AutoAdminLogon / hide last user | **Kept** | Guides user to Entra sign-in after join |
| Block input / UI forms (ServiceUI-style) | **Removed** | Heavy dependency, hard to test, not required for escrow |

**Clarification:** “Graph permissions” in original docs usually meant **reading** keys as an admin or other Graph automation—not what the device needs to **escrow**. DMU-Clean only escrows via the built-in cmdlet.

---

### G. Phase 3 – OneDrive / user data

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| ODSyncUtil / custom binaries for sync status | **Removed** | Binary dependency, licensing/support burden, fragile under SYSTEM |
| Multiple scheduled tasks (backup, clear cache, sync status) | **Collapsed** into one Phase 3 script | Less task sprawl; easier to reason about |
| OneDrive KFM / policy nudge | **Kept** (`Enable-OneDriveKFM`) | Valid tenant-side preparation |
| User file backup | **Kept** as safety-net **robocopy** into `OneDrive\DMU-Backup` | Protects data without external tools |
| Assume full KFM completes under SYSTEM | **Documented limit** | Real KFM still needs user Entra sign-in |

**Added:** `Get-OneDriveSyncStatus` as best-effort, no third-party EXE.

---

### H. Phase 4 – Cleanup

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Remove temp user, tasks, folders, reset registry | **Kept** and expanded in `Phase4-Cleanup.ps1` | Leave device in a normal state |
| `\AAD Migration\` task cleanup | **Kept** + **`\DMU\`** via `Unregister-DMUScheduledTask` | Cover both legacy and new task folders |
| Aggressive log deletion | **Logs preserved by default** | Support post-mortems; optional delete |

---

### I. Logging & telemetry

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| Transcript + PSFramework, duplicated in every script | **Shared** `Initialize-Logging` / `Stop-Logging` | DRY |
| Decrypt PAT and **upload logs to GitHub** | **Removed** | High risk (secrets on disk, broad token use), not needed for migration success |
| Enhanced log helpers everywhere | Simple `Write-DMULog` + optional PSF | Enough for operations |

---

### J. Scheduling model

| Original | DMU-Clean | Why |
|----------|-----------|-----|
| RunOnce + many tasks under `\AAD Migration\` | RunOnce in phases + optional **`Register-MigrationPhaseTasks`** under `\DMU\` | Operators can choose simple RunOnce or visible, restartable tasks |
| — | **Added** `Register/Get/Unregister-DMUScheduledTask` | First-class, tested API for task lifecycle |

---

### K. Quality / security tooling (new in DMU-Clean)

| Added | Why |
|-------|-----|
| Pester 5 tests | Catch regressions on password gen, status matrix, WhatIf paths, config validation |
| `docs/` (Architecture, Phases, Security, Troubleshooting, …) | Original was hard to operate from code alone |
| Module manifest `DMU.psd1` | Optional packaging; clear exports |
| `.gitignore` for real config, secrets, test results | Prevent secret leaks |

---

## 3. What was deliberately *not* ported

| Original piece | Reason removed |
|----------------|----------------|
| Hardcoded TenantID / `Default1234` | Security defect |
| GitHub PAT + log upload pipeline | Secret handling, scope creep, failure mode unrelated to join |
| Enhanced module / ModuleStarter stack | Opaque, hard to vendor, blocked a clean readable path |
| ODSyncUtil and similar binaries | External dependency; replaceable with policy + robocopy + user sign-in |
| ServiceUI / interactive “migration in progress” forms | Complexity; optional UX, not core |
| Graph-based admin reporting in-script | Not required for device-side escrow/join; keep tool free of app registrations |
| Archive / duplicate README / dead paths | Noise |

---

## 4. End-to-end flow (same goal, cleaner path)

**Original (conceptual):**  
Setup → big bootstrap → config/secrets → status → temp user → PPKG → reboot → BitLocker + UI/registry → OneDrive tasks/binaries → cleanup tasks → optional log ship to GitHub

**DMU-Clean:**  
`Setup.ps1` → `Start-DeviceMigration` (config, status, strong temp admin, stage scripts, optional `\DMU\` tasks) → **Phase1** PPKG → **Phase2** escrow + registry → **Phase3** KFM + safety-net copy → **Phase4** cleanup

Same business outcome: **Workgroup / domain / hybrid → Entra Join + Intune, with BitLocker key in Entra and user data pointed at OneDrive**, without carrying forward the insecure and unmaintainable parts of the original toolkit.

---

## Related docs

- [Architecture](Architecture.md)
- [Phases](Phases.md)
- [Security](Security.md)
- [Scheduled Tasks](Scheduled-Tasks.md)
