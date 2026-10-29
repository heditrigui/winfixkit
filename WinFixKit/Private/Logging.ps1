function Get-FixKitLogFile {
    <#
    .SYNOPSIS
        Returns the full path of today's log file, creating the log folder if needed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dir = Get-FixKitLogPath
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -Confirm:$false
    }
    Join-Path -Path $dir -ChildPath ('WinFixKit-{0:yyyyMMdd}.log' -f (Get-Date))
}

function Write-FixLog {
    <#
    .SYNOPSIS
        Appends one line to the WinFixKit log file and echoes it to the verbose stream.
    .EXAMPLE
        Write-FixLog -Message 'Flushed DNS cache' -Level INFO
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DRYRUN', 'ACTION')]
        [string]$Level = 'INFO'
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1,-6}] [{2}] {3}' -f (Get-Date), $Level, [Environment]::UserName, $Message
    Write-Verbose -Message $line
    try {
        Add-Content -LiteralPath (Get-FixKitLogFile) -Value $line -Encoding UTF8 -ErrorAction Stop -WhatIf:$false -Confirm:$false
    }
    catch {
        # Logging must never break a repair; surface it once and move on.
        Write-Warning -Message "WinFixKit could not write to its log file: $($_.Exception.Message)"
    }
}
