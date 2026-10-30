function Remove-SavedCredential {
    <#
    .SYNOPSIS
        Deletes saved Credential Manager entries for a chosen target.
    .DESCRIPTION
        Fixes repeated password prompts, account lockouts after a password change, and
        "wrong user" connections to file shares, printers, Outlook or Teams. Removes every
        saved credential whose target matches -Target (wildcards allowed), for the current user.
        To avoid wiping everything by mistake, the pattern must contain at least 3 characters
        that are not wildcards. No admin rights needed.
    .EXAMPLE
        Remove-SavedCredential -Target '*fileserver01*' -WhatIf
    .EXAMPLE
        Get-SavedCredentialTarget
        Remove-SavedCredential -Target 'MicrosoftOffice16_Data:*'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        [Parameter(Mandatory)]
        [SupportsWildcards()]
        [ValidateScript({
                if (($_ -replace '[\*\?\[\]\s]', '').Length -ge 3) { return $true }
                throw "Target '$_' is too broad. Use at least 3 characters that are not wildcards, for example '*fileserver*'."
            })]
        [string]$Target
    )

    Write-FixLog -Message "Remove-SavedCredential started (Target='$Target', WhatIf=$WhatIfPreference)"
    $matching = @(Get-SavedCredentialTarget -Target $Target)
    if (-not $matching) {
        Write-FixLog -Message "No saved credential matches '$Target'." -Level WARN
        Write-Warning -Message "No saved credential matches '$Target'. Run Get-SavedCredentialTarget to see what is saved."
        return
    }

    foreach ($cred in $matching) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step "Delete saved credential ($($cred.Type), user $($cred.UserName))" -Target $cred.Target -ScriptBlock {
            [WinFixKit.CredMan]::Delete($cred.Target, $cred.TypeId)
        }
    }
}
