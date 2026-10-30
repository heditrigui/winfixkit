@{
    RootModule           = 'WinFixKit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '3d670a23-776c-4c5a-ad04-9d67b77497e4'
    Author               = 'Hedi Trigui'
    Copyright            = '(c) 2026 Hedi Trigui. MIT License.'
    Description          = 'Safe, logged, dry-run-first Windows repair toolkit for IT support: network reset, Windows Update repair, SFC/DISM, print spooler, temp cleanup, Store apps, startup review, debloat and a system snapshot report.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Get-SystemSnapshot'
        'Export-SystemSnapshot'
        'Reset-NetworkStack'
        'Repair-WindowsUpdate'
        'Repair-SystemImage'
        'Reset-PrintSpooler'
        'Invoke-TempCleanup'
        'Repair-StoreApp'
        'Get-StartupItem'
        'Get-DebloatCandidate'
        'Invoke-Debloat'
        'Get-FixKitDiagnosis'
        'Export-FixKitTicketBundle'
        'Reset-TeamsCache'
        'Reset-OutlookCache'
        'Reset-OneDriveSync'
        'Restart-AudioService'
        'Sync-WindowsTime'
        'Get-SavedCredentialTarget'
        'Remove-SavedCredential'
        'Restore-MappedDrive'
        'Get-FixKitCatalog'
        'Get-FixKitLogPath'
        'Show-FixKitGui'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'Repair', 'Troubleshooting', 'HelpDesk', 'SysAdmin', 'ITSupport', 'WPF', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
