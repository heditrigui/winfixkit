function Repair-SystemImage {
    <#
    .SYNOPSIS
        Runs DISM and SFC to check and repair Windows system files.
    .DESCRIPTION
        Default (repair):  DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow.
        -ScanOnly:         DISM /CheckHealth, then sfc /verifyonly (changes nothing).
        DISM order matters: it repairs the component store that SFC copies good files from.
        By default DISM may use Windows Update as its repair source, which is Windows' own
        mechanism. Pass -Source with a mounted install.wim/esd to repair fully offline.
        Requires admin rights. Can take 10-30 minutes.
    .EXAMPLE
        Repair-SystemImage -ScanOnly
    .EXAMPLE
        Repair-SystemImage -Source 'wim:D:\sources\install.wim:1'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Only check for corruption; do not repair.
        [switch]$ScanOnly,

        # DISM repair source, e.g. 'wim:D:\sources\install.wim:1'. Implies /LimitAccess.
        [string]$Source
    )

    Write-FixLog -Message "Repair-SystemImage started (ScanOnly=$ScanOnly, Source='$Source', WhatIf=$WhatIfPreference)"
    Assert-FixKitElevation -FixName 'Repair-SystemImage' -DryRun $WhatIfPreference

    if ($ScanOnly) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'DISM CheckHealth' -Target 'Component store' -ScriptBlock {
            dism.exe /Online /Cleanup-Image /CheckHealth
        }
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'SFC verify only' -Target 'System files' -ScriptBlock {
            sfc.exe /verifyonly
        }
        return
    }

    $dismArgs = @('/Online', '/Cleanup-Image', '/RestoreHealth')
    if ($Source) { $dismArgs += @("/Source:$Source", '/LimitAccess') }

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'DISM RestoreHealth' -Target 'Component store' -ScriptBlock {
        dism.exe @dismArgs
    }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'SFC scan and repair' -Target 'System files' -ScriptBlock {
        sfc.exe /scannow
    }
    Write-FixLog -Message 'SFC details are in %windir%\Logs\CBS\CBS.log'
}
