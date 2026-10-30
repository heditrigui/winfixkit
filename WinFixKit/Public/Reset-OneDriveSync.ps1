function Reset-OneDriveSync {
    <#
    .SYNOPSIS
        Resets the OneDrive sync client for the current user.
    .DESCRIPTION
        Runs "OneDrive.exe /reset", which drops the sync state and makes OneDrive compare
        everything again. Your files are not deleted, but the first sync afterwards can take a
        while. OneDrive is started again if it does not restart by itself.
        No admin rights needed.
    .EXAMPLE
        Reset-OneDriveSync -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param()

    Write-FixLog -Message "Reset-OneDriveSync started (WhatIf=$WhatIfPreference)"
    $exe = Get-OneDrivePath
    if (-not $exe) {
        Write-FixLog -Message 'OneDrive.exe not found.' -Level WARN
        return New-StepResult -Step 'Reset OneDrive' -Target 'OneDrive.exe' -Status 'Skipped' -Message 'OneDrive is not installed'
    }

    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Reset sync client' -Target $exe -ScriptBlock {
        Start-Process -FilePath $exe -ArgumentList '/reset' -ErrorAction Stop
        Start-Sleep -Seconds 10
        'Reset requested.'
    }
    Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Start OneDrive' -Target $exe -ScriptBlock {
        if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { 'Already running.' }
        else { Start-Process -FilePath $exe -ErrorAction Stop; 'Started.' }
    }
}

function Get-OneDrivePath {
    $candidates = @(
        Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
        Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'
        if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe' }
    )
    $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
