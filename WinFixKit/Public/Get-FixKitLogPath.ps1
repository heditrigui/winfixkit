function Get-FixKitLogPath {
    <#
    .SYNOPSIS
        Returns the folder WinFixKit writes its logs to.
    .DESCRIPTION
        Defaults to %LOCALAPPDATA%\WinFixKit\Logs. Set the WINFIXKIT_LOGDIR environment
        variable to log somewhere else (for example a share collected by your helpdesk).
    .EXAMPLE
        Get-FixKitLogPath | Invoke-Item
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:WINFIXKIT_LOGDIR) { return $env:WINFIXKIT_LOGDIR }
    Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WinFixKit\Logs'
}
