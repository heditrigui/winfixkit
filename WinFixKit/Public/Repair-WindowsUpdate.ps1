function Repair-WindowsUpdate {
    <#
    .SYNOPSIS
        Resets the Windows Update services and cache folders.
    .DESCRIPTION
        Stops wuauserv, BITS, CryptSvc and msiserver, renames SoftwareDistribution and
        catroot2 to "<name>.bak-<timestamp>" (renamed, not deleted, so you can roll back),
        then starts the services again. Windows rebuilds both folders on the next scan.
        Requires admin rights.
    .EXAMPLE
        Repair-WindowsUpdate -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param()

    Write-FixLog -Message "Repair-WindowsUpdate started (WhatIf=$WhatIfPreference)"
    Assert-FixKitElevation -FixName 'Repair-WindowsUpdate' -DryRun $WhatIfPreference

    $services = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folders = @(
        Join-Path $env:SystemRoot 'SoftwareDistribution'
        Join-Path $env:SystemRoot 'System32\catroot2'
    )

    foreach ($name in $services) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Stop service' -Target $name -ScriptBlock {
            Stop-Service -Name $name -Force -ErrorAction Stop -Confirm:$false
        }
    }

    foreach ($folder in $folders) {
        $newName = '{0}.bak-{1}' -f (Split-Path $folder -Leaf), $stamp
        Invoke-FixStep -Cmdlet $PSCmdlet -Step "Rename cache to $newName" -Target $folder -ScriptBlock {
            if (Test-Path -LiteralPath $folder) {
                Rename-Item -LiteralPath $folder -NewName $newName -ErrorAction Stop -Confirm:$false
            }
            else {
                "Not present, nothing to rename."
            }
        }
    }

    # Start in reverse order; always attempted so a failed rename never leaves updates disabled.
    [array]::Reverse($services)
    foreach ($name in $services) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Start service' -Target $name -ScriptBlock {
            Start-Service -Name $name -ErrorAction Stop -Confirm:$false
        }
    }
}
