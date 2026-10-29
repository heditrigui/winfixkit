function Reset-NetworkStack {
    <#
    .SYNOPSIS
        Flushes DNS and resets Winsock and the TCP/IP stack.
    .DESCRIPTION
        The classic "internet is broken but the cable is fine" fix:
          1. Clear-DnsClientCache        (same as ipconfig /flushdns)
          2. netsh winsock reset          (admin)
          3. netsh int ip reset           (admin)
          4. ipconfig /release + /renew   (only with -RenewLease; drops the connection briefly)
        A restart is needed for the Winsock and IP resets to take effect.
        Use -DnsOnly to just flush the DNS cache, which does not need admin rights.
    .EXAMPLE
        Reset-NetworkStack -WhatIf
        Shows every step without changing anything.
    .EXAMPLE
        Reset-NetworkStack -DnsOnly
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Only flush the DNS resolver cache (no admin needed).
        [switch]$DnsOnly,

        # Also release and renew DHCP leases on all adapters.
        [switch]$RenewLease
    )

    Write-FixLog -Message "Reset-NetworkStack started (DnsOnly=$DnsOnly, RenewLease=$RenewLease, WhatIf=$WhatIfPreference)"

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Flush DNS cache' -Target 'DNS resolver' -ScriptBlock { Clear-DnsClientCache -ErrorAction Stop }
    if ($DnsOnly) { return }

    Assert-FixKitElevation -FixName 'Reset-NetworkStack' -DryRun $WhatIfPreference

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Reset Winsock catalog' -Target 'Winsock' -ScriptBlock { netsh.exe winsock reset }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Reset TCP/IP stack' -Target 'TCP/IP' -ScriptBlock { netsh.exe int ip reset }

    if ($RenewLease) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Release DHCP leases' -Target 'All adapters' -ScriptBlock { ipconfig.exe /release }
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Renew DHCP leases' -Target 'All adapters' -ScriptBlock { ipconfig.exe /renew }
    }

    if (-not $WhatIfPreference) {
        Write-Warning -Message 'Restart the computer to finish the Winsock and TCP/IP reset.'
    }
}
