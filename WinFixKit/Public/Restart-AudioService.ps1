function Restart-AudioService {
    <#
    .SYNOPSIS
        Restarts the Windows audio services.
    .DESCRIPTION
        The fix for "no sound" or a red X on the speaker icon when the hardware is fine.
        Restarts AudioEndpointBuilder (which also restarts Audiosrv) and makes sure Audiosrv
        is running afterwards. Sound cuts out for a moment. Requires admin rights.
    .EXAMPLE
        Restart-AudioService -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WinFixKit.StepResult')]
    param()

    Write-FixLog -Message "Restart-AudioService started (WhatIf=$WhatIfPreference)"
    Assert-FixKitElevation -FixName 'Restart-AudioService' -DryRun $WhatIfPreference

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Restart service' -Target 'AudioEndpointBuilder' -ScriptBlock {
        Restart-Service -Name AudioEndpointBuilder -Force -ErrorAction Stop -Confirm:$false
    }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Start service' -Target 'Audiosrv' -ScriptBlock {
        Start-Service -Name Audiosrv -ErrorAction Stop -Confirm:$false
        "Audiosrv is $((Get-Service -Name Audiosrv).Status)."
    }
}
