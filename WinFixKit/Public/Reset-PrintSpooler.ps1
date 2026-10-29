function Reset-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the print spooler and clears stuck print jobs.
    .DESCRIPTION
        Stops the Spooler service, deletes queued job files from
        %SystemRoot%\System32\spool\PRINTERS, and starts the service again.
        Use -KeepQueue to only restart the service. Requires admin rights.
    .EXAMPLE
        Reset-PrintSpooler -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Restart the service without deleting queued jobs.
        [switch]$KeepQueue
    )

    Write-FixLog -Message "Reset-PrintSpooler started (KeepQueue=$KeepQueue, WhatIf=$WhatIfPreference)"
    Assert-FixKitElevation -FixName 'Reset-PrintSpooler' -DryRun $WhatIfPreference

    $queue = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Stop service' -Target 'Spooler' -ScriptBlock {
        Stop-Service -Name Spooler -Force -ErrorAction Stop -Confirm:$false
    }

    if (-not $KeepQueue) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Delete queued print jobs' -Target $queue -ScriptBlock {
            $jobs = @(Get-ChildItem -LiteralPath $queue -File -Force -ErrorAction Stop)
            $jobs | Remove-Item -Force -ErrorAction Stop -Confirm:$false
            "Removed $($jobs.Count) queued file(s)."
        }
    }

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Start service' -Target 'Spooler' -ScriptBlock {
        Start-Service -Name Spooler -ErrorAction Stop -Confirm:$false
    }
}
