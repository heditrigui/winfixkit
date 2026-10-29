function Get-StartupItem {
    <#
    .SYNOPSIS
        Lists programs that start with Windows, and whether each is enabled. Read-only.
    .DESCRIPTION
        Reads the Run/RunOnce registry keys (user, machine and 32-bit) and both Startup folders,
        and checks the StartupApproved keys that Task Manager uses to enable or disable items.
        To disable something, use Task Manager > Startup apps; WinFixKit only reports.
    .EXAMPLE
        Get-StartupItem | Where-Object Enabled | Format-Table Name, Scope, Command
    #>
    [CmdletBinding()]
    [OutputType('WinFixKit.StartupItem')]
    param()

    $approvedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Hive = 'HKCU'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Scope = 'User' }
        @{ Hive = 'HKCU'; Key = 'Software\Microsoft\Windows\CurrentVersion\RunOnce'; Approved = $null; Scope = 'User' }
        @{ Hive = 'HKLM'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Scope = 'Machine' }
        @{ Hive = 'HKLM'; Key = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32'; Scope = 'Machine' }
        @{ Hive = 'HKLM'; Key = 'Software\Microsoft\Windows\CurrentVersion\RunOnce'; Approved = $null; Scope = 'Machine' }
    )

    foreach ($src in $sources) {
        $key = Get-Item -LiteralPath "$($src.Hive):\$($src.Key)" -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($valueName in $key.GetValueNames() | Where-Object { $_ }) {
            $approved = if ($src.Approved) { Get-StartupApprovedValue -Hive $src.Hive -Path "$approvedRoot\$($src.Approved)" -Name $valueName }
            New-StartupItem -Name $valueName -Command ([string]$key.GetValue($valueName)) `
                -Location "$($src.Hive):\$($src.Key)" -Scope $src.Scope -Enabled (ConvertFrom-StartupApprovedValue -Value $approved)
        }
    }

    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Hive = 'HKCU'; Scope = 'User' }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Hive = 'HKLM'; Scope = 'Machine' }
    )
    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') {
            $approved = Get-StartupApprovedValue -Hive $folder.Hive -Path "$approvedRoot\StartupFolder" -Name $file.Name
            New-StartupItem -Name $file.BaseName -Command $file.FullName -Location $folder.Path `
                -Scope $folder.Scope -Enabled (ConvertFrom-StartupApprovedValue -Value $approved)
        }
    }
}

function ConvertFrom-StartupApprovedValue {
    <#
    .SYNOPSIS
        Decodes a StartupApproved binary value. Even first byte (02, 06) = enabled, odd (03, 07) = disabled.
        No value means Task Manager never touched the item, so it is enabled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [byte[]]$Value
    )

    if (-not $Value -or $Value.Length -eq 0) { return $true }
    ($Value[0] -band 1) -eq 0
}

function Get-StartupApprovedValue {
    param([string]$Hive, [string]$Path, [string]$Name)

    $key = Get-Item -LiteralPath "$($Hive):\$Path" -ErrorAction SilentlyContinue
    if ($key) { $key.GetValue($Name) }
}

function New-StartupItem {
    param([string]$Name, [string]$Command, [string]$Location, [string]$Scope, [bool]$Enabled)

    [pscustomobject]@{
        PSTypeName = 'WinFixKit.StartupItem'
        Name       = $Name
        Enabled    = $Enabled
        Scope      = $Scope
        Command    = $Command
        Location   = $Location
    }
}
