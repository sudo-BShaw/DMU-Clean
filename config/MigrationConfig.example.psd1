@{
    # ============================================================
    # Device Migration Utility - Example Configuration
    # ============================================================
    # Copy this file to MigrationConfig.psd1 and fill in real values.
    # NEVER commit MigrationConfig.psd1 with real secrets.
    # ============================================================

    # Path used for migration working files
    MigrationPath       = 'C:\ProgramData\AADMigration'

    # OneDrive settings
    UseOneDriveKFM      = $true
    InstallOneDrive     = $true

    # Target Entra ID Tenant ID (GUID)
    # Replace with your real Tenant ID
    TenantID            = '00000000-0000-0000-0000-000000000000'

    # Optional deferral settings (leave empty if not used)
    DeferDeadline       = ''          # e.g. '2026-12-31 18:00:00'
    DeferTimes          = ''

    # Temporary local account used during migration
    # Password is generated at runtime (strong random) – do not hardcode
    TempUser            = 'MigrationInProgress'
    # TempPass is intentionally omitted – generated securely by the tool

    # Provisioning package location (after decryption / placement)
    # Prefer a path under MigrationPath or a controlled location
    ProvisioningPack    = 'C:\ProgramData\AADMigration\Files\YourPackage.ppkg'
    ProvisioningPackName = 'YourPackage.ppkg'

    # Logging
    LogsPath            = 'C:\Logs'
    JobName             = 'AAD_Migration'

    # Optional: GitHub integration for private PPKG / log upload
    # Leave empty or remove if not used
    # GitHubOwner         = 'your-org-or-user'
    # GitHubRepo          = 'your-private-vault-or-logs-repo'
}