function Invoke-Debloat {
    <#
    .SYNOPSIS
        Removes preinstalled consumer apps from the curated list in Get-DebloatCandidate.
    .DESCRIPTION
        Optional. Removes the apps for the current user only, which needs no admin rights.
        -IncludeProvisioned also removes them from the Windows image so new user profiles
        do not get them (admin). Only names on the curated list are accepted.
        Every app removed here can be reinstalled from the Microsoft Store.
    .EXAMPLE
        Invoke-Debloat -WhatIf
    .EXAMPLE
        Invoke-Debloat -Name Microsoft.BingNews, Microsoft.GetHelp
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Apps to remove. Defaults to every installed app on the curated list.
        [ValidateScript({
                if ($script:DebloatList.ContainsKey($_)) { return $true }
                throw "'$_' is not on the WinFixKit debloat list. See Get-DebloatCandidate -ListOnly."
            })]
        [string[]]$Name,

        # Also remove the provisioned copy so new users do not get the app (admin).
        [switch]$IncludeProvisioned
    )

    Write-FixLog -Message "Invoke-Debloat started (Name='$($Name -join ',')', IncludeProvisioned=$IncludeProvisioned, WhatIf=$WhatIfPreference)"
    if ($IncludeProvisioned) {
        Assert-FixKitElevation -FixName 'Invoke-Debloat -IncludeProvisioned' -DryRun $WhatIfPreference
    }
    Import-FixKitAppx

    if (-not $Name) { $Name = @($script:DebloatList.Keys | Sort-Object) }

    foreach ($app in $Name) {
        $packages = @(Get-AppxPackage -Name $app)
        foreach ($pkg in $packages) {
            Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Remove app (current user)' -Target $pkg.Name -ScriptBlock {
                Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop -Confirm:$false
            }
        }

        if ($IncludeProvisioned) {
            $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $app)
            foreach ($prov in $provisioned) {
                Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Remove provisioned app' -Target $prov.DisplayName -ScriptBlock {
                    $null = Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                }
            }
        }
    }
}
