function Get-FixKitDiagnosis {
    <#
    .SYNOPSIS
        "Fix my PC": runs quick read-only health checks and recommends which fixes to run.
    .DESCRIPTION
        Checks network (adapter, gateway, DNS), pending reboot, Windows Update, the print
        spooler, free disk space, system file health, the clock, audio and mapped drives.
        Nothing is changed. Each result names the catalog fix that addresses it (the Fix
        column), e.g. DNS failing -> 'dns' (Flush DNS cache). The full DISM health check
        only runs when elevated; otherwise recent crashes are used as a hint.
    .EXAMPLE
        Get-FixKitDiagnosis | Format-Table Status, Check, Detail, FixTitle
    .EXAMPLE
        Get-FixKitDiagnosis | Where-Object Fix | Select-Object -ExpandProperty Fix -Unique
        Lists the recommended catalog fix ids.
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.DiagnosisResult')]
    param(
        # Host name used to test DNS resolution.
        [string]$DnsTestName = 'www.msftconnecttest.com',

        # Free space (percent) on the system drive below which cleanup is recommended.
        [ValidateRange(1, 90)]
        [int]$MinFreePercent = 15
    )

    Write-FixLog -Message 'Diagnosis started'
    $dnsArgs = @{ Name = $DnsTestName }
    $diskArgs = @{ MinFreePercent = $MinFreePercent }
    $titles = @{}
    foreach ($item in Get-FixKitCatalog) { $titles[$item.Id] = $item.Title }

    $checks = [ordered]@{
        'Network adapter'   = { Test-DiagNetworkAdapter }
        'Default gateway'   = { Test-DiagGateway }
        'DNS resolution'    = { Test-DiagDnsResolution @dnsArgs }
        'Pending restart'   = { Test-DiagPendingReboot }
        'Windows Update'    = { Test-DiagWindowsUpdate }
        'Print spooler'     = { Test-DiagSpooler }
        'Disk space'        = { Test-DiagDiskSpace @diskArgs }
        'System files'      = { Test-DiagSystemFile }
        'Clock and time'    = { Test-DiagTime }
        'Audio'             = { Test-DiagAudio }
        'Mapped drives'     = { Test-DiagMappedDrive }
    }

    foreach ($name in $checks.Keys) {
        try {
            $r = & $checks[$name]
        }
        catch {
            $r = @{ Status = 'Skipped'; Detail = "Check failed: $($_.Exception.Message)" }
        }
        $fix = if ($r.ContainsKey('Fix')) { $r.Fix } else { $null }
        $result = [pscustomobject]@{
            PSTypeName = 'WinFixKit.DiagnosisResult'
            Check      = $name
            Status     = $r.Status
            Detail     = $r.Detail
            Fix        = $fix
            FixTitle   = if ($fix) { $titles[$fix] } else { $null }
        }
        Write-FixLog -Message ("Diagnosis: {0} = {1}. {2}{3}" -f $name, $result.Status, $result.Detail, $(if ($fix) { " Recommended: $fix" }))
        $result
    }
}

# Each check returns @{ Status = 'OK' | 'Warning' | 'Problem' | 'Skipped'; Detail = '...'; Fix = '<catalog id>' }.

function Test-DiagNetworkAdapter {
    $up = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
    if ($up) { return @{ Status = 'OK'; Detail = "Connected: $(($up.Name) -join ', ')" } }
    @{ Status = 'Problem'; Detail = 'No physical network adapter is connected. Check the cable or Wi-Fi.' }
}

function Test-DiagGateway {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if (-not $route) { return @{ Status = 'Problem'; Detail = 'No default gateway. The PC has no route to the internet.'; Fix = 'network' } }
    $gateway = $route.NextHop
    if (Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue) {
        return @{ Status = 'OK'; Detail = "Gateway $gateway replies." }
    }
    @{ Status = 'Warning'; Detail = "Gateway $gateway does not reply to ping (some routers block ping)."; Fix = 'network' }
}

function Test-DiagDnsResolution {
    param([string]$Name)
    try {
        $answer = Resolve-DnsName -Name $Name -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.PSObject.Properties['IPAddress'] } | Select-Object -First 1
        $ip = if ($answer) { " ($($answer.IPAddress))" } else { '' }
        @{ Status = 'OK'; Detail = "$Name resolves$ip." }
    }
    catch {
        @{ Status = 'Problem'; Detail = "Cannot resolve $Name. $($_.Exception.Message)"; Fix = 'dns' }
    }
}

function Test-DiagPendingReboot {
    if (Test-PendingReboot) { return @{ Status = 'Warning'; Detail = 'Updates or file operations are waiting for a restart. Restart before running other fixes.' } }
    @{ Status = 'OK'; Detail = 'No restart pending.' }
}

function Test-DiagWindowsUpdate {
    $disabled = @(Get-Service -Name wuauserv, bits -ErrorAction Stop | Where-Object StartType -eq 'Disabled')
    if ($disabled) {
        return @{ Status = 'Problem'; Detail = "Update service disabled: $(($disabled.Name) -join ', ')."; Fix = 'wu' }
    }
    $filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Level = 2; StartTime = (Get-Date).AddDays(-7) }
    $errors = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 50 -ErrorAction SilentlyContinue)
    if ($errors.Count -ge 2) {
        return @{ Status = 'Warning'; Detail = "$($errors.Count) Windows Update install failures in the last 7 days."; Fix = 'wu' }
    }
    @{ Status = 'OK'; Detail = 'Update services enabled, no repeated install failures.' }
}

function Test-DiagSpooler {
    $svc = Get-Service -Name Spooler -ErrorAction Stop
    if ($svc.Status -ne 'Running') { return @{ Status = 'Problem'; Detail = "Print spooler is $($svc.Status)."; Fix = 'spooler' } }
    $cutoff = (Get-Date).AddMinutes(-30)
    $stuck = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { Get-PrintJob -PrinterObject $_ -ErrorAction SilentlyContinue } |
            Where-Object { "$($_.JobStatus)" -match 'Error|Blocked|Paused' -or $_.SubmittedTime -lt $cutoff })
    if ($stuck) { return @{ Status = 'Warning'; Detail = "$($stuck.Count) print job(s) stuck in the queue."; Fix = 'spooler' } }
    @{ Status = 'OK'; Detail = 'Spooler running, queue clear.' }
}

function Test-DiagDiskSpace {
    param([int]$MinFreePercent)
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
    $free = if ($disk.Size) { [math]::Round(100 * $disk.FreeSpace / $disk.Size, 0) } else { 100 }
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    if ($free -lt [math]::Min(10, $MinFreePercent)) { return @{ Status = 'Problem'; Detail = "$($env:SystemDrive) has $free% free ($freeGB GB)."; Fix = 'temp-system' } }
    if ($free -lt $MinFreePercent) { return @{ Status = 'Warning'; Detail = "$($env:SystemDrive) has $free% free ($freeGB GB)."; Fix = 'temp' } }
    @{ Status = 'OK'; Detail = "$($env:SystemDrive) has $free% free ($freeGB GB)." }
}

function Test-DiagSystemFile {
    if (Test-FixKitElevation) {
        $global:LASTEXITCODE = 0
        $out = (dism.exe /Online /Cleanup-Image /CheckHealth 2>&1) -join ' '
        if ($LASTEXITCODE -eq 0 -and $out -match 'No component store corruption') { return @{ Status = 'OK'; Detail = 'DISM found no component store corruption.' } }
        return @{ Status = 'Problem'; Detail = 'DISM reports component store corruption or could not check.'; Fix = 'sfc' }
    }
    $filter = @{ LogName = 'System'; Id = 41, 1001, 6008; StartTime = (Get-Date).AddDays(-7) }
    $crashes = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 20 -ErrorAction SilentlyContinue)
    if ($crashes) { return @{ Status = 'Warning'; Detail = "$($crashes.Count) crash or unexpected shutdown event(s) in 7 days."; Fix = 'sfc-scan' } }
    @{ Status = 'Skipped'; Detail = 'No recent crashes. A full system file check needs admin: use "Check system files".' }
}

function Test-DiagTime {
    $svc = Get-Service -Name W32Time -ErrorAction Stop
    if ($svc.StartType -eq 'Disabled') { return @{ Status = 'Problem'; Detail = 'Windows Time service is disabled.'; Fix = 'time' } }
    $global:LASTEXITCODE = 0
    $status = w32tm.exe /query /status 2>&1
    if ($LASTEXITCODE -ne 0) {
        # On PCs outside a domain W32Time is trigger-started, so "Stopped" is normal there.
        if ($svc.Status -ne 'Running') { return @{ Status = 'OK'; Detail = 'Windows Time starts on demand (not running right now).' } }
        return @{ Status = 'Warning'; Detail = 'Windows Time is running but cannot report its sync status.'; Fix = 'time' }
    }
    # The value after "Last Successful Sync Time:" is localized, so only check that a source is set.
    $source = ($status | Where-Object { $_ -match '^\s*Source:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
    if ($source -match 'Local CMOS Clock|Free-running') {
        return @{ Status = 'Warning'; Detail = "Clock is not syncing with a time server (source: $source)."; Fix = 'time' }
    }
    @{ Status = 'OK'; Detail = $(if ($source) { "Syncing with $source." } else { 'Windows Time is running.' }) }
}

function Test-DiagAudio {
    $svc = @(Get-Service -Name Audiosrv, AudioEndpointBuilder -ErrorAction Stop | Where-Object Status -ne 'Running')
    if ($svc) { return @{ Status = 'Problem'; Detail = "Audio service not running: $(($svc.Name) -join ', ')."; Fix = 'audio' } }
    @{ Status = 'OK'; Detail = 'Audio services running.' }
}

function Test-DiagMappedDrive {
    $maps = @(Get-PersistentDriveMapping)
    if (-not $maps) { return @{ Status = 'OK'; Detail = 'No persistent mapped drives.' } }
    $down = @($maps | Where-Object { -not (Test-Path -LiteralPath "$($_.Letter):\") })
    if ($down) { return @{ Status = 'Warning'; Detail = "Disconnected: $(($down | ForEach-Object { "$($_.Letter): $($_.RemotePath)" }) -join ', ')."; Fix = 'drives' } }
    @{ Status = 'OK'; Detail = "$($maps.Count) mapped drive(s) connected." }
}
