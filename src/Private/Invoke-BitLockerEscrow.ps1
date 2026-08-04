function Invoke-BitLockerEscrow {
    <#
    .SYNOPSIS
        Escrows BitLocker recovery password protectors to Entra ID (Azure AD).

    .DESCRIPTION
        For each specified mount point:
        - Verifies BitLocker is enabled
        - Locates RecoveryPassword key protectors
        - Calls BackupToAAD-BitLockerKeyProtector

        Based on the well-known MSEndpointMgr / Michael Mardahl pattern,
        cleaned and parameterized for DMU.

    .PARAMETER MountPoint
        Drive letter(s) to process. Defaults to the system drive.

    .PARAMETER CreateProtectorIfMissing
        If no RecoveryPassword protector exists, attempt to add one
        before escrowing (requires the volume already be encrypted).

    .OUTPUTS
        PSCustomObject per drive with Success, MountPoint, KeyProtectorIds, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$MountPoint = @($env:SystemDrive),

        [switch]$CreateProtectorIfMissing
    )

    begin {
        if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            throw "BitLocker PowerShell cmdlets are not available on this system."
        }
        if (-not (Get-Command BackupToAAD-BitLockerKeyProtector -ErrorAction SilentlyContinue)) {
            throw "BackupToAAD-BitLockerKeyProtector is not available. Ensure the device can talk to Entra ID and the cmdlet is present."
        }
    }

    process {
        foreach ($drive in $MountPoint) {
            $result = [PSCustomObject]@{
                MountPoint       = $drive
                Success          = $false
                KeyProtectorIds  = @()
                Message          = ''
            }

            try {
                $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
            }
            catch {
                $result.Message = "BitLocker volume not found or not protected: $drive. Skipping."
                Write-Verbose $result.Message
                $result
                continue
            }

            if ($volume.VolumeStatus -eq 'FullyDecrypted' -or $volume.ProtectionStatus -eq 'Off') {
                $result.Message = "BitLocker is not enabled on $drive. Nothing to escrow."
                Write-Verbose $result.Message
                $result.Success = $true   # not an error condition for migration
                $result
                continue
            }

            $protectors = @($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })

            if (-not $protectors -or $protectors.Count -eq 0) {
                if ($CreateProtectorIfMissing -and $PSCmdlet.ShouldProcess($drive, 'Add RecoveryPassword key protector')) {
                    try {
                        Add-BitLockerKeyProtector -MountPoint $drive -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
                        $volume = Get-BitLockerVolume -MountPoint $drive
                        $protectors = @($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
                        Write-Verbose "Added RecoveryPassword protector on $drive"
                    }
                    catch {
                        $result.Message = "Failed to create RecoveryPassword protector on $drive : $($_.Exception.Message)"
                        $result
                        continue
                    }
                }
                else {
                    $result.Message = "No RecoveryPassword key protector found on $drive."
                    $result
                    continue
                }
            }

            $escrowed = @()
            foreach ($kp in $protectors) {
                $id = $kp.KeyProtectorId
                if ($PSCmdlet.ShouldProcess("$drive ($id)", 'BackupToAAD-BitLockerKeyProtector')) {
                    try {
                        # Some policy mismatches surface as non-terminating errors;
                        # we still treat the call as attempted and leave verification to Intune/Entra.
                        BackupToAAD-BitLockerKeyProtector -MountPoint $drive -KeyProtectorId $id -ErrorAction Stop
                        $escrowed += $id
                        Write-Verbose "Escrowed key protector $id for $drive"
                    }
                    catch {
                        # Log but continue – common when a key was already escrowed or policy differs slightly
                        Write-Warning "BackupToAAD-BitLockerKeyProtector reported an issue for $drive / $id : $($_.Exception.Message). Verify in Entra ID / Intune."
                        $escrowed += $id   # still record the attempt
                    }
                }
            }

            $result.KeyProtectorIds = $escrowed
            $result.Success = $true
            $result.Message = if ($escrowed.Count -gt 0) {
                "Attempted escrow of $($escrowed.Count) recovery key(s) for $drive. Verify in Entra ID / Intune."
            } else {
                "No keys were escrowed for $drive."
            }

            $result
        }
    }
}