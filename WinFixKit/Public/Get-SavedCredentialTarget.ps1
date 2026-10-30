function Get-SavedCredentialTarget {
    <#
    .SYNOPSIS
        Lists the targets saved in Windows Credential Manager for the current user. Read-only.
    .DESCRIPTION
        Shows what is saved (target, type, user name, last change), never the passwords.
        Use it to find the target to pass to Remove-SavedCredential.
    .EXAMPLE
        Get-SavedCredentialTarget | Where-Object Target -like '*fileserver*'
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.SavedCredential')]
    param(
        # Only return targets that match this wildcard pattern.
        [SupportsWildcards()]
        [string]$Target = '*'
    )

    Initialize-FixKitCredMan
    foreach ($cred in [WinFixKit.CredMan]::Enumerate() | Sort-Object Target) {
        if ($cred.Target -notlike $Target) { continue }
        [pscustomobject]@{
            PSTypeName  = 'WinFixKit.SavedCredential'
            Target      = $cred.Target
            Type        = ConvertTo-CredentialTypeName -Type $cred.Type
            UserName    = $cred.UserName
            LastWritten = $cred.LastWritten
            TypeId      = $cred.Type
        }
    }
}
