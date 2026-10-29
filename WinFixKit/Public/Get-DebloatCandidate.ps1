function Get-DebloatCandidate {
    <#
    .SYNOPSIS
        Lists the consumer apps WinFixKit can remove, and whether each is installed. Read-only.
    .DESCRIPTION
        The list is deliberately conservative: no Photos, Calculator, Media Player, Terminal,
        Store, Xbox/gaming components or anything a business is likely to rely on.
        Every app on it can be reinstalled from the Microsoft Store.
    .EXAMPLE
        Get-DebloatCandidate | Where-Object Installed
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.DebloatCandidate')]
    param(
        # Skip the installed check (fast, works without the Appx module).
        [switch]$ListOnly
    )

    if (-not $ListOnly) { Import-FixKitAppx }

    foreach ($app in $script:DebloatList.GetEnumerator() | Sort-Object Key) {
        $installed = if ($ListOnly) { $null } else { [bool](Get-AppxPackage -Name $app.Key) }
        [pscustomobject]@{
            PSTypeName  = 'WinFixKit.DebloatCandidate'
            Name        = $app.Key
            Description = $app.Value
            Installed   = $installed
        }
    }
}

# Package name -> friendly description. Edit here to change what debloat may remove.
$script:DebloatList = @{
    'Microsoft.BingNews'                   = 'Microsoft News'
    'Microsoft.BingWeather'                = 'Weather'
    'Microsoft.GetHelp'                    = 'Get Help'
    'Microsoft.Getstarted'                 = 'Tips'
    'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire Collection'
    'Microsoft.MicrosoftOfficeHub'         = 'Microsoft 365 (Office) hub app'
    'Microsoft.People'                     = 'People'
    'Microsoft.WindowsFeedbackHub'         = 'Feedback Hub'
    'Microsoft.WindowsMaps'                = 'Maps'
    'Microsoft.ZuneVideo'                  = 'Movies & TV'
    'Microsoft.MixedReality.Portal'        = 'Mixed Reality Portal'
    'Microsoft.Microsoft3DViewer'          = '3D Viewer'
    'Microsoft.SkypeApp'                   = 'Skype'
    'Microsoft.549981C3F5F10'              = 'Cortana'
    'Clipchamp.Clipchamp'                  = 'Clipchamp video editor'
    'MicrosoftTeams'                       = 'Teams (personal)'
}
