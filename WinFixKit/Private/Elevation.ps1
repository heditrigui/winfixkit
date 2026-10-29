function Test-FixKitElevation {
    <#
    .SYNOPSIS
        Returns $true when the current process runs with administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-FixKitElevation {
    <#
    .SYNOPSIS
        Throws a friendly error when a fix needs admin rights and the session is not elevated.
        Dry runs (-WhatIf) never need elevation, so they are always allowed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FixName,

        [bool]$DryRun
    )

    if ($DryRun -or (Test-FixKitElevation)) { return }

    $message = "$FixName needs administrator rights. Re-run it from an elevated PowerShell, use -WhatIf for a dry run, or launch it from the WinFixKit GUI, which asks for elevation only for this fix."
    Write-FixLog -Message $message -Level ERROR
    throw [System.UnauthorizedAccessException]::new($message)
}
