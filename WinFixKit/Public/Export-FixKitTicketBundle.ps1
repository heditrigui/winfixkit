function Export-FixKitTicketBundle {
    <#
    .SYNOPSIS
        Zips everything a helpdesk ticket needs into one file: snapshot, diagnosis, logs and fix results.
    .DESCRIPTION
        The bundle contains:
          snapshot.html / snapshot.json   system snapshot report
          diagnosis.txt                   "Fix my PC" check results
          logs\WinFixKit-*.log            WinFixKit logs from the last -Days days
          logs\FixResults-*.jsonl         every fix step run in that period, with its output
        Saved to the Reports folder next to the logs unless -Path is given. The zip includes
        the computer name, user name and IP configuration, so share it only with your helpdesk.
    .EXAMPLE
        Export-FixKitTicketBundle
    .EXAMPLE
        Export-FixKitTicketBundle -Days 3 -Path "$env:USERPROFILE\Desktop\ticket.zip"
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        # Output .zip file. Defaults to Reports\Ticket-<computer>-<timestamp>.zip.
        [string]$Path,

        # How many days of logs and fix results to include (1 = today only).
        [ValidateRange(1, 30)]
        [int]$Days = 1,

        # Leave out the diagnosis (it pings the gateway and resolves DNS).
        [switch]$SkipDiagnosis
    )

    Write-FixLog -Message "Ticket bundle started (Days=$Days, SkipDiagnosis=$SkipDiagnosis)"
    if (-not $Path) {
        $dir = Join-Path (Split-Path (Get-FixKitLogPath) -Parent) 'Reports'
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false }
        $Path = Join-Path $dir ('Ticket-{0}-{1:yyyyMMdd-HHmmss}.zip' -f $env:COMPUTERNAME, (Get-Date))
    }

    $staging = Join-Path ([IO.Path]::GetTempPath()) ('WinFixKit-ticket-{0}' -f [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path (Join-Path $staging 'logs') -Force -WhatIf:$false
    try {
        $snapshot = Get-SystemSnapshot
        $null = $snapshot | Export-SystemSnapshot -Format Html -Path (Join-Path $staging 'snapshot.html')
        $null = $snapshot | Export-SystemSnapshot -Format Json -Path (Join-Path $staging 'snapshot.json')

        if (-not $SkipDiagnosis) {
            Get-FixKitDiagnosis | Format-Table Status, Check, Detail, FixTitle -AutoSize -Wrap | Out-String -Width 200 |
                Set-Content -LiteralPath (Join-Path $staging 'diagnosis.txt') -Encoding UTF8 -WhatIf:$false
        }

        # Log last: the snapshot and diagnosis above add their own lines to today's log.
        Write-FixLog -Message "Ticket bundle: collecting logs into $Path"
        $logDir = Get-FixKitLogPath
        foreach ($offset in 0..($Days - 1)) {
            $day = (Get-Date).AddDays(-$offset)
            foreach ($file in (Join-Path $logDir ('WinFixKit-{0:yyyyMMdd}.log' -f $day)), (Get-FixKitResultFile -Date $day)) {
                if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $staging 'logs') -WhatIf:$false }
            }
        }

        $readme = @(
            "WinFixKit ticket bundle"
            "Computer: $env:COMPUTERNAME   User: $env:USERDOMAIN\$env:USERNAME   Created: $('{0:yyyy-MM-dd HH:mm}' -f (Get-Date))"
            ''
            'snapshot.html   system snapshot (open in a browser)'
            'snapshot.json   same data, machine readable'
            'diagnosis.txt   "Fix my PC" check results'
            'logs\           WinFixKit logs and FixResults (every fix step with its output)'
        )
        Set-Content -LiteralPath (Join-Path $staging 'README.txt') -Value $readme -Encoding UTF8 -WhatIf:$false

        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $Path -Force -WhatIf:$false
        Write-FixLog -Message "Ticket bundle saved to $Path"
        Get-Item -LiteralPath $Path
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
    }
}
