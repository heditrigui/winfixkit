<#
.SYNOPSIS
    Launches the WinFixKit GUI. Double-click WinFixKit.cmd or run: .\Start-FixKit.ps1
.DESCRIPTION
    Runs as a standard user. Fixes that need administrator rights ask for elevation
    (UAC) one at a time, in their own window.
#>
[CmdletBinding()]
param()

$manifest = Join-Path $PSScriptRoot 'WinFixKit\WinFixKit.psd1'

# WPF needs a single-threaded apartment; relaunch with -STA if this host is MTA.
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    return
}

Import-Module $manifest -Force
try {
    Show-FixKitGui
}
catch {
    Add-Type -AssemblyName PresentationFramework
    $null = [System.Windows.MessageBox]::Show("WinFixKit could not start:`n`n$($_.Exception.Message)", 'WinFixKit', 'OK', 'Error')
    throw
}
