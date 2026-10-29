function Repair-StoreApp {
    <#
    .SYNOPSIS
        Re-registers Microsoft Store apps for the current user.
    .DESCRIPTION
        Fixes Store apps that will not open, crash on launch or vanished from Start by
        re-registering each package from its existing AppXManifest.xml. Nothing is downloaded
        and no admin rights are needed. Framework packages are skipped.
    .EXAMPLE
        Repair-StoreApp -Name 'Microsoft.WindowsStore'
    .EXAMPLE
        Repair-StoreApp -WhatIf
        Lists every package that would be re-registered.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Package name filter, wildcards allowed. Defaults to every app for the current user.
        [SupportsWildcards()]
        [string]$Name = '*'
    )

    Write-FixLog -Message "Repair-StoreApp started (Name='$Name', WhatIf=$WhatIfPreference)"
    Import-FixKitAppx

    $packages = Get-AppxPackage -Name $Name |
        Where-Object { -not $_.IsFramework -and $_.InstallLocation } |
        Sort-Object Name

    if (-not $packages) {
        Write-FixLog -Message "No Store packages match '$Name'." -Level WARN
        return
    }

    foreach ($pkg in $packages) {
        $manifest = Join-Path $pkg.InstallLocation 'AppXManifest.xml'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Re-register app' -Target $pkg.Name -ScriptBlock {
            Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
        }
    }
}

function Import-FixKitAppx {
    # The Appx module is Windows PowerShell only; PowerShell 7 loads it through the compatibility layer.
    if (Get-Command -Name Get-AppxPackage -ErrorAction SilentlyContinue) { return }
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Import-Module -Name Appx -UseWindowsPowerShell -ErrorAction Stop -WarningAction SilentlyContinue
    }
    else {
        Import-Module -Name Appx -ErrorAction Stop
    }
}
