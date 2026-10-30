function Restore-MappedDrive {
    <#
    .SYNOPSIS
        Reconnects persistent mapped network drives that show as disconnected.
    .DESCRIPTION
        For each drive saved under HKCU\Network that is not reachable through its letter:
          1. checks that the share itself is reachable (if not, the mapping is left alone)
          2. removes the stale connection and maps the drive again as persistent.
        Drives that already work are skipped. Run it as the signed-in user, NOT elevated:
        an elevated session has its own, separate set of mapped drives.
    .EXAMPLE
        Restore-MappedDrive -WhatIf
    .EXAMPLE
        Restore-MappedDrive -DriveLetter S
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Only these drive letters, e.g. 'S', 'T'. Defaults to all persistent mappings.
        [ValidatePattern('^[A-Za-z]:?$')]
        [string[]]$DriveLetter
    )

    Write-FixLog -Message "Restore-MappedDrive started (DriveLetter='$($DriveLetter -join ',')', WhatIf=$WhatIfPreference)"
    if (Test-FixKitElevation) {
        Write-Warning -Message 'This session is elevated, and elevated sessions do not see the user''s mapped drives. Run Restore-MappedDrive from a normal PowerShell window.'
    }

    $mappings = @(Get-PersistentDriveMapping)
    if ($DriveLetter) {
        $wanted = $DriveLetter | ForEach-Object { $_.TrimEnd(':').ToUpper() }
        $mappings = @($mappings | Where-Object { $_.Letter -in $wanted })
    }
    if (-not $mappings) {
        Write-FixLog -Message 'No persistent mapped drives found.' -Level WARN
        return
    }

    foreach ($map in $mappings) {
        $drive = "$($map.Letter):"
        if (Test-Path -LiteralPath "$drive\") {
            Write-FixLog -Message "$drive ($($map.RemotePath)) is connected; skipped."
            New-StepResult -Step 'Check mapped drive' -Target "$drive $($map.RemotePath)" -Status 'Skipped' -Message 'Already connected'
            continue
        }
        if (-not (Test-Path -LiteralPath $map.RemotePath)) {
            Write-FixLog -Message "$drive cannot be restored: $($map.RemotePath) is unreachable. Mapping kept." -Level WARN
            New-StepResult -Step 'Check mapped drive' -Target "$drive $($map.RemotePath)" -Status 'Failed' -Message 'Share unreachable (check VPN/network). Mapping kept.'
            continue
        }
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Reconnect mapped drive' -Target "$drive $($map.RemotePath)" -ScriptBlock {
            $null = net.exe use $drive /delete /y 2>&1
            net.exe use $drive $map.RemotePath /persistent:yes
        }
    }
}

function Get-PersistentDriveMapping {
    <#
    .SYNOPSIS
        Reads the user's persistent drive mappings from HKCU\Network. Read-only.
    #>
    [CmdletBinding()]
    param()

    foreach ($key in Get-ChildItem -Path 'HKCU:\Network' -ErrorAction SilentlyContinue) {
        $remote = $key.GetValue('RemotePath')
        if (-not $remote) { continue }
        [pscustomobject]@{
            Letter     = $key.PSChildName.ToUpper()
            RemotePath = [string]$remote
            UserName   = [string]$key.GetValue('UserName')
        }
    }
}
