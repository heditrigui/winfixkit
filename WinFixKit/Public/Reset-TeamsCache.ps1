function Reset-TeamsCache {
    <#
    .SYNOPSIS
        Clears the Microsoft Teams cache for the current user (new and classic Teams).
    .DESCRIPTION
        Fixes Teams that will not sign in, shows stale chats or uses lots of memory.
        Closes Teams, then renames its cache folder to "<name>.bak-<timestamp>" (renamed,
        not deleted, so you can roll back). Teams rebuilds the cache at next start; you may
        need to sign in again. No admin rights needed.
          New Teams:     %LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams
          Classic Teams: %APPDATA%\Microsoft\Teams
    .EXAMPLE
        Reset-TeamsCache -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param()

    Write-FixLog -Message "Reset-TeamsCache started (WhatIf=$WhatIfPreference)"
    $folders = @(
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
        Join-Path $env:APPDATA 'Microsoft\Teams'
    )
    Reset-AppCacheFolder -Cmdlet $PSCmdlet -AppName 'Teams' -ProcessName 'ms-teams', 'Teams' -Folder $folders
}

function Reset-AppCacheFolder {
    <#
    .SYNOPSIS
        Shared steps for cache resets: stop the app's processes, then rename each cache folder that exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string[]]$ProcessName,
        [Parameter(Mandatory)][string[]]$Folder
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Invoke-FixStep -Cmdlet $Cmdlet -Step "Close $AppName" -Target ($ProcessName -join ', ') -ScriptBlock {
        $running = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
        $running | Stop-Process -Force -ErrorAction Stop -Confirm:$false
        "Closed $($running.Count) process(es)."
        if ($running) { Start-Sleep -Seconds 2 }
    }

    $existing = @($Folder | Where-Object { Test-Path -LiteralPath $_ })
    if (-not $existing) {
        Write-FixLog -Message "$AppName cache folders not found; nothing to reset." -Level WARN
        return New-StepResult -Step "Rename $AppName cache" -Target ($Folder -join '; ') -Status 'Skipped' -Message 'No cache folder found'
    }
    foreach ($path in $existing) {
        $newName = '{0}.bak-{1}' -f (Split-Path $path -Leaf), $stamp
        Invoke-FixStep -Cmdlet $Cmdlet -Step "Rename cache to $newName" -Target $path -ScriptBlock {
            Rename-Item -LiteralPath $path -NewName $newName -ErrorAction Stop -Confirm:$false
        }
    }
}
