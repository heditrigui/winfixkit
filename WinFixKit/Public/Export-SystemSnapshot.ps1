function Export-SystemSnapshot {
    <#
    .SYNOPSIS
        Saves a system snapshot report as HTML, JSON or text, and returns the file.
    .DESCRIPTION
        Handy to attach to a ticket. The HTML report is a single self-contained file that
        flags common problems (low disk space, pending reboot, unhealthy disks, recent errors).
        Default location: the "Reports" folder next to the WinFixKit logs.
    .EXAMPLE
        Export-SystemSnapshot | Invoke-Item
    .EXAMPLE
        Export-SystemSnapshot -Format Json -Path .\pc42.json
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [ValidateSet('Html', 'Json', 'Text')]
        [string]$Format = 'Html',

        # Output file. Defaults to Reports\Snapshot-<computer>-<timestamp>.<ext>.
        [string]$Path,

        # Use an existing snapshot instead of collecting a new one.
        [Parameter(ValueFromPipeline)]
        [psobject]$InputObject,

        [int]$ErrorHours = 24
    )

    process {
        $snapshot = if ($InputObject) { $InputObject } else { Get-SystemSnapshot -ErrorHours $ErrorHours }

        if (-not $Path) {
            $dir = Join-Path (Split-Path (Get-FixKitLogPath) -Parent) 'Reports'
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            $ext = @{ Html = 'html'; Json = 'json'; Text = 'txt' }[$Format]
            $Path = Join-Path $dir ('Snapshot-{0}-{1:yyyyMMdd-HHmmss}.{2}' -f $env:COMPUTERNAME, (Get-Date), $ext)
        }

        $content = switch ($Format) {
            'Html' { ConvertTo-SnapshotHtml -Snapshot $snapshot }
            'Json' { $snapshot | ConvertTo-Json -Depth 5 }
            'Text' { ConvertTo-SnapshotText -Snapshot $snapshot }
        }

        Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
        Write-FixLog -Message "Snapshot report saved to $Path"
        Get-Item -LiteralPath $Path
    }
}

function Get-SnapshotFinding {
    <#
    .SYNOPSIS
        Turns a snapshot into a short list of things worth looking at.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][psobject]$Snapshot)

    foreach ($disk in $Snapshot.Disks) {
        if ($disk.FreePercent -lt 10) {
            [pscustomobject]@{ Severity = 'bad'; Text = "Drive $($disk.Drive) is almost full ($($disk.FreePercent)% free, $($disk.FreeGB) GB)." }
        }
        elseif ($disk.FreePercent -lt 20) {
            [pscustomobject]@{ Severity = 'warn'; Text = "Drive $($disk.Drive) is getting full ($($disk.FreePercent)% free)." }
        }
    }
    foreach ($pd in $Snapshot.PhysicalDisks) {
        if ($pd.Health -and $pd.Health -ne 'Healthy') {
            [pscustomobject]@{ Severity = 'bad'; Text = "Physical disk '$($pd.Name)' reports health: $($pd.Health)." }
        }
    }
    if ($Snapshot.System.PendingReboot) {
        [pscustomobject]@{ Severity = 'warn'; Text = 'A restart is pending (updates or file operations are waiting).' }
    }
    $errorCount = @($Snapshot.RecentErrors).Count
    if ($errorCount -gt 0) {
        [pscustomobject]@{ Severity = 'warn'; Text = "$errorCount critical/error event(s) in the System and Application logs recently." }
    }
    if (-not @($Snapshot.Network).Count) {
        [pscustomobject]@{ Severity = 'bad'; Text = 'No network adapter is connected.' }
    }
}

function ConvertTo-SnapshotHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Snapshot)

    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }

    $findings = @(Get-SnapshotFinding -Snapshot $Snapshot)
    $findingHtml = if ($findings) {
        ($findings | ForEach-Object { '<li class="{0}">{1}</li>' -f $_.Severity, (& $enc $_.Text) }) -join ''
    }
    else { '<li class="ok">No problems spotted.</li>' }

    $sections = [ordered]@{
        'System'               = @($Snapshot.System)
        'Hardware'             = @($Snapshot.Hardware)
        'Disks'                = @($Snapshot.Disks)
        'Physical disks'       = @($Snapshot.PhysicalDisks)
        'Network (connected)'  = @($Snapshot.Network)
        'Recent errors'        = @($Snapshot.RecentErrors)
    }

    $body = foreach ($title in $sections.Keys) {
        $rows = $sections[$title]
        '<h2>{0}</h2>' -f (& $enc $title)
        if (-not $rows -or -not $rows[0]) { '<p class="muted">Nothing to show.</p>'; continue }

        if ($rows.Count -eq 1 -and $title -in 'System', 'Hardware') {
            # Single objects read better as a two-column key/value table.
            '<table class="kv">'
            foreach ($p in $rows[0].PSObject.Properties) { '<tr><th>{0}</th><td>{1}</td></tr>' -f (& $enc $p.Name), (& $enc $p.Value) }
            '</table>'
        }
        else {
            $props = $rows[0].PSObject.Properties.Name
            '<table><tr>' + (($props | ForEach-Object { '<th>{0}</th>' -f (& $enc $_) }) -join '') + '</tr>'
            foreach ($r in $rows) { '<tr>' + (($props | ForEach-Object { '<td>{0}</td>' -f (& $enc $r.$_) }) -join '') + '</tr>' }
            '</table>'
        }
    }

    $style = @'
:root { --bg:#f7f8fa; --card:#fff; --text:#1d2330; --muted:#6b7280; --line:#e5e7eb; --accent:#2563eb; --bad:#b91c1c; --warn:#b45309; --ok:#15803d; }
@media (prefers-color-scheme: dark) { :root { --bg:#111418; --card:#1a1e24; --text:#e6e8eb; --muted:#9aa3ad; --line:#2a2f37; --accent:#6ea8fe; --bad:#f87171; --warn:#fbbf24; --ok:#4ade80; } }
body { font-family: "Segoe UI", system-ui, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 24px; }
main { max-width: 1100px; margin: 0 auto; }
h1 { margin: 0 0 4px; font-size: 24px; } h2 { font-size: 16px; margin: 28px 0 8px; color: var(--accent); }
.muted { color: var(--muted); }
ul.findings { list-style: none; padding: 12px 16px; background: var(--card); border: 1px solid var(--line); border-radius: 8px; }
ul.findings li { padding: 3px 0; } li.bad { color: var(--bad); } li.warn { color: var(--warn); } li.ok { color: var(--ok); }
table { border-collapse: collapse; width: 100%; background: var(--card); border: 1px solid var(--line); font-size: 13px; }
th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { color: var(--muted); font-weight: 600; } table.kv th { width: 180px; }
'@

    @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>System snapshot - $(& $enc $Snapshot.System.ComputerName)</title><style>$style</style></head>
<body><main>
<h1>System snapshot: $(& $enc $Snapshot.System.ComputerName)</h1>
<p class="muted">Generated $(& $enc ('{0:yyyy-MM-dd HH:mm}' -f $Snapshot.GeneratedAt)) by WinFixKit</p>
<h2>Findings</h2><ul class="findings">$findingHtml</ul>
$($body -join "`n")
</main></body></html>
"@
}

function ConvertTo-SnapshotText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Snapshot)

    $out = [System.Text.StringBuilder]::new()
    $null = $out.AppendLine("WinFixKit system snapshot - $($Snapshot.System.ComputerName) - $('{0:yyyy-MM-dd HH:mm}' -f $Snapshot.GeneratedAt)")
    $null = $out.AppendLine()
    $null = $out.AppendLine('FINDINGS')
    $findings = @(Get-SnapshotFinding -Snapshot $Snapshot)
    if ($findings) { foreach ($f in $findings) { $null = $out.AppendLine("  [$($f.Severity.ToUpper())] $($f.Text)") } }
    else { $null = $out.AppendLine('  No problems spotted.') }

    foreach ($name in 'System', 'Hardware') {
        $null = $out.AppendLine(); $null = $out.AppendLine($name.ToUpper())
        $null = $out.Append(($Snapshot.$name | Format-List | Out-String).Trim()); $null = $out.AppendLine()
    }
    foreach ($name in 'Disks', 'PhysicalDisks', 'Network', 'RecentErrors') {
        $null = $out.AppendLine(); $null = $out.AppendLine($name.ToUpper())
        $null = $out.Append(($Snapshot.$name | Format-Table -AutoSize -Wrap | Out-String -Width 200).Trim()); $null = $out.AppendLine()
    }
    $out.ToString()
}
