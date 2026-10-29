function Show-FixKitGui {
    <#
    .SYNOPSIS
        Opens the WinFixKit window.
    .DESCRIPTION
        The GUI starts in dry-run mode. It runs as a standard user and only asks for
        administrator rights (UAC) when you run a fix that needs them.
    .EXAMPLE
        Show-FixKitGui
    #>
    [CmdletBinding()]
    param()

    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'The WinFixKit GUI needs a single-threaded apartment. Start it with Start-FixKit.ps1, or run: powershell.exe -STA -Command Show-FixKitGui'
    }

    Write-FixLog -Message "GUI opened (PowerShell $($PSVersionTable.PSVersion), elevated=$(Test-FixKitElevation))"
    $window = New-FixKitWindow
    $null = $window.ShowDialog()
    Write-FixLog -Message 'GUI closed'
}
