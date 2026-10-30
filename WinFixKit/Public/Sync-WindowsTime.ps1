function Sync-WindowsTime {
    <#
    .SYNOPSIS
        Starts the Windows Time service and forces a clock resync.
    .DESCRIPTION
        A clock that is a few minutes off breaks Kerberos sign-in, TLS and Teams/Outlook
        connections. Starts W32Time if needed, reloads its configuration and runs
        "w32tm /resync /force" against the configured time source (domain controller or
        time.windows.com). Requires admin rights.
    .EXAMPLE
        Sync-WindowsTime -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WinFixKit.StepResult')]
    param()

    Write-FixLog -Message "Sync-WindowsTime started (WhatIf=$WhatIfPreference)"
    Assert-FixKitElevation -FixName 'Sync-WindowsTime' -DryRun $WhatIfPreference

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Start service' -Target 'W32Time' -ScriptBlock {
        Start-Service -Name W32Time -ErrorAction Stop -Confirm:$false
    }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Reload time configuration' -Target 'W32Time' -ScriptBlock {
        w32tm.exe /config /update
    }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Force time resync' -Target 'W32Time' -ScriptBlock {
        w32tm.exe /resync /force
    }
}
