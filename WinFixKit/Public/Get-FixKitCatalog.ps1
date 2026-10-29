function Get-FixKitCatalog {
    <#
    .SYNOPSIS
        Lists every fix WinFixKit offers, with whether it needs admin and whether it changes things.
    .DESCRIPTION
        The GUI builds its buttons from this list, so adding a fix here adds it to the GUI.
    .EXAMPLE
        Get-FixKitCatalog | Format-Table Title, RequiresAdmin, Destructive
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.CatalogItem')]
    param()

    $items = @(
        @{ Id = 'snapshot'; Category = 'Diagnose'; Title = 'System snapshot report'; Command = 'Export-SystemSnapshot'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $false; ReadOnly = $true
            Description = 'OS, hardware, disks, network and recent errors as an HTML report you can attach to a ticket.' }
        @{ Id = 'startup'; Category = 'Diagnose'; Title = 'Review startup apps'; Command = 'Get-StartupItem'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $false; ReadOnly = $true
            Description = 'Lists everything that starts with Windows and whether it is enabled.' }
        @{ Id = 'sfc-scan'; Category = 'Diagnose'; Title = 'Check system files'; Command = 'Repair-SystemImage'; Parameters = @{ ScanOnly = $true }
            RequiresAdmin = $true; Destructive = $false; ReadOnly = $false
            Description = 'DISM CheckHealth + SFC verify only. Reports corruption without fixing it.' }
        @{ Id = 'dns'; Category = 'Network'; Title = 'Flush DNS cache'; Command = 'Reset-NetworkStack'; Parameters = @{ DnsOnly = $true }
            RequiresAdmin = $false; Destructive = $false; ReadOnly = $false
            Description = 'Clears cached DNS lookups. Safe first step when one site will not load.' }
        @{ Id = 'network'; Category = 'Network'; Title = 'Reset network stack'; Command = 'Reset-NetworkStack'; Parameters = @{}
            RequiresAdmin = $true; Destructive = $true; ReadOnly = $false
            Description = 'Flush DNS, reset Winsock and TCP/IP. Needs a restart afterwards.' }
        @{ Id = 'wu'; Category = 'Repair'; Title = 'Repair Windows Update'; Command = 'Repair-WindowsUpdate'; Parameters = @{}
            RequiresAdmin = $true; Destructive = $true; ReadOnly = $false
            Description = 'Restart update services and rename the SoftwareDistribution and catroot2 caches.' }
        @{ Id = 'sfc'; Category = 'Repair'; Title = 'Repair system files'; Command = 'Repair-SystemImage'; Parameters = @{}
            RequiresAdmin = $true; Destructive = $false; ReadOnly = $false
            Description = 'DISM RestoreHealth, then SFC /scannow. Takes 10-30 minutes.' }
        @{ Id = 'spooler'; Category = 'Repair'; Title = 'Fix stuck printing'; Command = 'Reset-PrintSpooler'; Parameters = @{}
            RequiresAdmin = $true; Destructive = $true; ReadOnly = $false
            Description = 'Stop the print spooler, delete stuck jobs, start it again.' }
        @{ Id = 'store'; Category = 'Repair'; Title = 'Re-register Store apps'; Command = 'Repair-StoreApp'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $false; ReadOnly = $false
            Description = 'Re-registers Store apps for this user from their local manifests.' }
        @{ Id = 'temp'; Category = 'Clean up'; Title = 'Clean my temp files'; Command = 'Invoke-TempCleanup'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $true; ReadOnly = $false
            Description = 'Deletes files older than 2 days from your %TEMP% folder.' }
        @{ Id = 'temp-system'; Category = 'Clean up'; Title = 'Deep disk cleanup'; Command = 'Invoke-TempCleanup'; Parameters = @{ IncludeSystem = $true; ComponentStore = $true }
            RequiresAdmin = $true; Destructive = $true; ReadOnly = $false
            Description = 'User and Windows temp folders, plus DISM component store cleanup.' }
        @{ Id = 'debloat-list'; Category = 'Debloat (optional)'; Title = 'Show removable apps'; Command = 'Get-DebloatCandidate'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $false; ReadOnly = $true
            Description = 'Shows the curated list of consumer apps and which are installed.' }
        @{ Id = 'debloat'; Category = 'Debloat (optional)'; Title = 'Remove consumer apps'; Command = 'Invoke-Debloat'; Parameters = @{}
            RequiresAdmin = $false; Destructive = $true; ReadOnly = $false
            Description = 'Removes the installed apps from that list for this user. Reinstallable from the Store.' }
    )

    $order = 'Id', 'Category', 'Title', 'Description', 'Command', 'Parameters', 'RequiresAdmin', 'Destructive', 'ReadOnly'
    foreach ($item in $items) {
        $props = [ordered]@{}
        foreach ($key in $order) { $props[$key] = $item[$key] }
        $obj = [pscustomobject]$props
        $obj.PSObject.TypeNames.Insert(0, 'WinFixKit.CatalogItem')
        $obj
    }
}
