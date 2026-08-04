# Architecture

## Goals

DMU-Clean is a modular rewrite of the classic Intune device migration toolkit. Design priorities:

1. **Security** – no hardcoded passwords or tenant secrets in source
2. **Modularity** – small Public/Private functions instead of monolithic scripts
3. **Predictable hand-off** – phases chain via RunOnce and/or Task Scheduler
4. **Testability** – core helpers covered by Pester 5
5. **Operational clarity** – thin `Setup.ps1`, explicit config, shared logging

## High-level flow

```
┌─────────────────────┐
│  Setup.ps1          │  elevate, load functions
│  Start-DeviceMigration │  config, status, temp user, stage scripts
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Phase1-EntraJoin   │  apply PPKG → Entra Join
└──────────┬──────────┘
           │ reboot + RunOnce / scheduled task
           ▼
┌─────────────────────┐
│  Phase2-BitLocker   │  BackupToAAD recovery keys + registry notice
└──────────┬──────────┘
           │ reboot
           ▼
┌─────────────────────┐
│  Phase3-OneDrive    │  KFM policy, start client, safety-net copy
└──────────┬──────────┘
           │ reboot
           ▼
┌─────────────────────┐
│  Phase4-Cleanup     │  remove temp user, tasks, working dir
└─────────────────────┘
```

## Repository layout

```
DMU-Clean/
├── Setup.ps1                 # Thin elevated entry point
├── config/
│   └── MigrationConfig.example.psd1
├── src/
│   ├── DMU.psd1 / DMU.psm1   # Optional module packaging
│   ├── Public/               # Exported / orchestrator functions
│   ├── Private/              # Internal helpers
│   └── Scripts/              # Phase1–4 executable scripts
├── tests/                    # Pester 5
└── docs/                     # This documentation
```

## Runtime working directory

During a migration, scripts and config are **staged** to:

```
C:\ProgramData\AADMigration\
├── MigrationConfig.psd1
├── Scripts\Phase*.ps1
├── Files\          (optional wallpaper, assets)
└── Logs\
```

Application logs default to `C:\Logs\` (transcript + optional PSFramework CSV).

## Join-state model

`Get-DeviceJoinStatus` parses `dsregcmd /status` into:

| Property | Meaning |
|----------|---------|
| `JoinType` | `Workgroup` \| `AzureAD` \| `Hybrid` \| `OnPrem` |
| `IsMDMEnrolled` | Intune URL present in dsregcmd output |
| `NeedsMigration` | `$true` unless pure Entra Join **and** MDM enrolled |

Only pure Entra + Intune is treated as “done.” Hybrid remains `NeedsMigration = $true`.

## Hand-off mechanisms

| Mechanism | Used by | Pros | Cons |
|-----------|---------|------|------|
| **RunOnce** (`HKLM\...\RunOnce`) | Phase scripts by default | Simple, runs once at next logon | Can be cleared; less visible |
| **Scheduled tasks** (`\DMU\`) | `-UseScheduledTasks` / helpers | Visible, SYSTEM, restartable | Must be cleaned up in Phase 4 |

Both can coexist. Phase 4 and `Unregister-DMUScheduledTask` clean the task folder.
