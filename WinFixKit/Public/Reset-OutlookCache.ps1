function Reset-OutlookCache {
    <#
    .SYNOPSIS
        Clears the classic Outlook cache for the current user.
    .DESCRIPTION
        Fixes Outlook problems such as stale shared calendars or folders and odd add-in
        behaviour. Closes Outlook and renames %LOCALAPPDATA%\Microsoft\Outlook\RoamCache
        to "RoamCache.bak-<timestamp>".
        -IncludeOfflineData also renames the .ost mailbox caches, so Outlook downloads the
        mailbox again. Use it for sync problems; it can take a while on large mailboxes.
        Nothing is deleted, and no admin rights are needed.
    .EXAMPLE
        Reset-OutlookCache -WhatIf
    .EXAMPLE
        Reset-OutlookCache -IncludeOfflineData
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        # Also rename *.ost files so the mailbox is downloaded again.
        [switch]$IncludeOfflineData
    )

    Write-FixLog -Message "Reset-OutlookCache started (IncludeOfflineData=$IncludeOfflineData, WhatIf=$WhatIfPreference)"
    $outlookData = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    Reset-AppCacheFolder -Cmdlet $PSCmdlet -AppName 'Outlook' -ProcessName 'OUTLOOK' -Folder (Join-Path $outlookData 'RoamCache')

    if ($IncludeOfflineData) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        foreach ($ost in @(Get-ChildItem -LiteralPath $outlookData -Filter '*.ost' -File -ErrorAction SilentlyContinue)) {
            Invoke-FixStep -Cmdlet $PSCmdlet -Step "Rename offline mailbox to $($ost.Name).bak-$stamp" -Target $ost.FullName -ScriptBlock {
                Rename-Item -LiteralPath $ost.FullName -NewName "$($ost.Name).bak-$stamp" -ErrorAction Stop -Confirm:$false
            }
        }
    }
}
