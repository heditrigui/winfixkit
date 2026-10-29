function Get-SystemSnapshot {
    <#
    .SYNOPSIS
        Collects a quick health snapshot of this PC. Read-only, no admin needed.
    .DESCRIPTION
        Gathers what a helpdesk tech asks for first: OS and build, uptime and pending reboot,
        hardware, disk space and health, network configuration, and recent critical/error
        events from the System and Application logs.
    .EXAMPLE
        Get-SystemSnapshot | Select-Object -ExpandProperty Disks
    .EXAMPLE
        Export-SystemSnapshot -Format Html
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.SystemSnapshot')]
    param(
        # How far back to look for error events.
        [ValidateRange(1, 720)]
        [int]$ErrorHours = 24,

        # Maximum number of error events to include.
        [ValidateRange(0, 500)]
        [int]$MaxEvents = 25
    )

    Write-FixLog -Message "Get-SystemSnapshot started (ErrorHours=$ErrorHours)"

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $cpu = @(Get-CimInstance -ClassName Win32_Processor)[0]
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $displayVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion

    $system = [pscustomobject]@{
        ComputerName  = $env:COMPUTERNAME
        User          = "$env:USERDOMAIN\$env:USERNAME"
        Domain        = $cs.Domain
        OS            = $os.Caption
        Version       = ('{0} (build {1})' -f $displayVersion, $os.BuildNumber).Trim()
        InstallDate   = $os.InstallDate
        LastBoot      = $os.LastBootUpTime
        Uptime        = Format-FixKitTimeSpan -TimeSpan ((Get-Date) - $os.LastBootUpTime)
        PendingReboot = Test-PendingReboot
        Elevated      = Test-FixKitElevation
    }

    $hardware = [pscustomobject]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        SerialNumber = $bios.SerialNumber
        BIOS         = '{0} ({1:yyyy-MM-dd})' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate
        CPU          = $cpu.Name.Trim()
        Cores        = '{0} cores / {1} threads' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
        MemoryGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        MemoryFreeGB = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)
    }

    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            [pscustomobject]@{
                Drive       = $_.DeviceID
                Label       = $_.VolumeName
                FileSystem  = $_.FileSystem
                SizeGB      = [math]::Round($_.Size / 1GB, 1)
                FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
                FreePercent = if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 0) } else { 0 }
            }
        })

    $physicalDisks = @(try {
            Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Name   = $_.FriendlyName
                    Media  = [string]$_.MediaType
                    Bus    = [string]$_.BusType
                    SizeGB = [math]::Round($_.Size / 1GB, 0)
                    Health = [string]$_.HealthStatus
                }
            }
        }
        catch { Write-FixLog -Message "Physical disk query failed: $($_.Exception.Message)" -Level WARN })

    $network = @(try {
            Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
                [pscustomobject]@{
                    Adapter = $_.InterfaceAlias
                    Type    = $_.NetAdapter.InterfaceDescription
                    IPv4    = (@($_.IPv4Address | Where-Object { $_ } | ForEach-Object IPAddress) -join ', ')
                    Gateway = (@($_.IPv4DefaultGateway | Where-Object { $_ } | ForEach-Object NextHop) -join ', ')
                    DNS     = (@($_.DNSServer | Where-Object { $_ -and $_.AddressFamily -eq 2 } | ForEach-Object ServerAddresses) -join ', ')
                    MAC     = $_.NetAdapter.MacAddress
                }
            }
        }
        catch { Write-FixLog -Message "Network query failed: $($_.Exception.Message)" -Level WARN })

    $events = @()
    if ($MaxEvents -gt 0) {
        $filter = @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-$ErrorHours) }
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{
                    Time    = $_.TimeCreated
                    Log     = $_.LogName
                    Level   = $_.LevelDisplayName
                    Source  = $_.ProviderName
                    EventId = $_.Id
                    Message = Get-FirstLine -Text $_.Message
                }
            })
    }

    [pscustomobject]@{
        PSTypeName    = 'WinFixKit.SystemSnapshot'
        GeneratedAt   = Get-Date
        System        = $system
        Hardware      = $hardware
        Disks         = $disks
        PhysicalDisks = $physicalDisks
        Network       = $network
        RecentErrors  = $events
    }
}

function Test-PendingReboot {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) { if (Test-Path -LiteralPath $key) { return $true } }
    $sm = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    [bool]$sm
}

function Format-FixKitTimeSpan {
    param([timespan]$TimeSpan)
    '{0}d {1}h {2}m' -f $TimeSpan.Days, $TimeSpan.Hours, $TimeSpan.Minutes
}

function Get-FirstLine {
    param([string]$Text, [int]$MaxLength = 200)

    if (-not $Text) { return '' }
    $line = ($Text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $line) { return '' }
    $line = $line.Trim()
    if ($line.Length -gt $MaxLength) { $line = $line.Substring(0, $MaxLength - 3) + '...' }
    $line
}
