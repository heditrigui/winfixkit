#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Variables set in BeforeDiscovery are used by -ForEach, which the analyzer cannot see.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# Tests only exercise read-only code paths, -WhatIf dry runs, and real deletes inside
# Pester's TestDrive. Nothing here changes the machine running the tests.

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\WinFixKit'
    $env:WINFIXKIT_LOGDIR = Join-Path ([IO.Path]::GetTempPath()) "WinFixKit-tests-$PID"
    Import-Module (Join-Path $script:ModuleRoot 'WinFixKit.psd1') -Force
}

AfterAll {
    Remove-Module WinFixKit -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $env:WINFIXKIT_LOGDIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\WINFIXKIT_LOGDIR -ErrorAction SilentlyContinue
}

Describe 'Module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'WinFixKit.psd1') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the functions listed in the manifest' {
        $manifest = Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'WinFixKit.psd1')
        $exported = (Get-Command -Module WinFixKit).Name | Sort-Object
        $exported | Should -Be ($manifest.FunctionsToExport | Sort-Object)
    }

    It 'gives every public function help with a synopsis and an example' {
        foreach ($cmd in Get-Command -Module WinFixKit) {
            $help = Get-Help $cmd.Name -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$($cmd.Name) needs a synopsis"
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$($cmd.Name) needs an example"
        }
    }

    It 'never downloads anything at runtime' {
        $pattern = 'Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadString|DownloadFile|WebClient|\biwr\b|\birm\b|curl(\.exe)?\s|wget\s'
        $hits = Get-ChildItem $script:ModuleRoot -Recurse -Filter *.ps1 | Select-String -Pattern $pattern
        $hits | Should -BeNullOrEmpty
    }
}

Describe 'Safety contract' {
    BeforeDiscovery {
        $changing = 'Reset-NetworkStack', 'Repair-WindowsUpdate', 'Repair-SystemImage', 'Reset-PrintSpooler',
        'Invoke-TempCleanup', 'Repair-StoreApp', 'Invoke-Debloat', 'Reset-TeamsCache', 'Reset-OutlookCache',
        'Reset-OneDriveSync', 'Restart-AudioService', 'Sync-WindowsTime', 'Remove-SavedCredential', 'Restore-MappedDrive'
        $destructive = 'Reset-NetworkStack', 'Repair-WindowsUpdate', 'Reset-PrintSpooler', 'Invoke-TempCleanup', 'Invoke-Debloat',
        'Reset-TeamsCache', 'Reset-OutlookCache', 'Reset-OneDriveSync', 'Remove-SavedCredential'
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
    }

    It '<_> supports -WhatIf and -Confirm' -ForEach $changing {
        $cmd = Get-Command $_
        $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        $cmd.Parameters.Keys | Should -Contain 'Confirm'
    }

    It '<_> asks for confirmation by default (ConfirmImpact High)' -ForEach $destructive {
        $attr = (Get-Command $_).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $attr.ConfirmImpact | Should -Be 'High'
    }

    It 'returns DryRun steps for every admin fix under -WhatIf, without needing admin' {
        $results = @(
            Reset-NetworkStack -WhatIf -RenewLease
            Repair-WindowsUpdate -WhatIf
            Repair-SystemImage -WhatIf
            Reset-PrintSpooler -WhatIf
            Invoke-TempCleanup -WhatIf -IncludeSystem -ComponentStore
            Restart-AudioService -WhatIf
            Sync-WindowsTime -WhatIf
        ) 6>$null
        $results.Count | Should -BeGreaterThan 10
        $results.Status | Sort-Object -Unique | Should -Be 'DryRun'
    }

    It 'refuses admin fixes without elevation when not a dry run' -Skip:$isAdmin {
        { Reset-PrintSpooler -Confirm:$false } | Should -Throw '*administrator*'
        { Sync-WindowsTime -Confirm:$false } | Should -Throw '*administrator*'
    }

    It 'only dry-runs or skips the per-user app fixes under -WhatIf' {
        $results = @(
            Reset-TeamsCache -WhatIf
            Reset-OutlookCache -WhatIf -IncludeOfflineData
            Reset-OneDriveSync -WhatIf
        ) 6>$null
        $results.Count | Should -BeGreaterThan 0
        $results.Status | Should -Not -Contain 'Done'
        $results.Status | Should -Not -Contain 'Failed'
    }

    It 'requires ShouldProcess on every catalog fix that changes something, and High impact when destructive' {
        foreach ($item in Get-FixKitCatalog | Where-Object { -not $_.ReadOnly }) {
            $cmd = Get-Command $item.Command
            $cmd.Parameters.Keys | Should -Contain 'WhatIf' -Because "$($item.Id) changes the system"
            if ($item.Destructive) {
                $attr = $cmd.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
                $attr.ConfirmImpact | Should -Be 'High' -Because "$($item.Id) is destructive"
            }
        }
    }
}

Describe 'Invoke-FixStep' {
    It 'does not run the script block under -WhatIf' {
        InModuleScope WinFixKit {
            function Test-Step {
                [CmdletBinding(SupportsShouldProcess)]
                param()
                Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Touch' -Target 'marker' -ScriptBlock { $script:ran = $true }
            }
            $script:ran = $false
            $r = Test-Step -WhatIf
            $r.Status | Should -Be 'DryRun'
            $script:ran | Should -BeFalse
        }
    }

    It 'reports Done with output, and Failed on a non-zero exit code' {
        InModuleScope WinFixKit {
            function Test-Step {
                [CmdletBinding(SupportsShouldProcess)]
                param([scriptblock]$Block)
                Invoke-FixStep -Cmdlet $PSCmdlet -Step 'Run' -Target 'test' -ScriptBlock $Block
            }
            $ok = Test-Step -Block { 'hello' } -Confirm:$false 6>$null
            $ok.Status | Should -Be 'Done'
            $ok.Output | Should -Be 'hello'

            $bad = Test-Step -Block { cmd.exe /c exit 3 } -Confirm:$false 6>$null
            $bad.Status | Should -Be 'Failed'
            $bad.Message | Should -Be 'Exit code 3'

            $thrown = Test-Step -Block { throw 'boom' } -Confirm:$false 6>$null
            $thrown.Status | Should -Be 'Failed'
            $thrown.Message | Should -Be 'boom'
        }
    }
}

Describe 'Logging' {
    It 'writes actions to the log file, including dry runs' {
        $null = Reset-NetworkStack -DnsOnly -WhatIf
        $log = Get-ChildItem -LiteralPath (Get-FixKitLogPath) -Filter 'WinFixKit-*.log' | Select-Object -First 1
        $log | Should -Not -BeNullOrEmpty
        Get-Content -LiteralPath $log.FullName -Raw | Should -Match '\[DRYRUN\] .*Would run: Flush DNS cache'
    }

    It 'honours WINFIXKIT_LOGDIR' {
        Get-FixKitLogPath | Should -Be $env:WINFIXKIT_LOGDIR
    }
}

Describe 'Invoke-TempCleanup' {
    BeforeEach {
        $dir = Join-Path $TestDrive 'temp'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $old = New-Item -Path (Join-Path $dir 'old.tmp') -ItemType File -Value 'x' -Force
        $old.LastWriteTime = (Get-Date).AddDays(-10)
        $null = New-Item -Path (Join-Path $dir 'new.tmp') -ItemType File -Value 'x' -Force
    }

    It 'plans only files older than the cutoff' {
        $plan = InModuleScope WinFixKit -Parameters @{ Dir = $dir } { param($Dir) Get-TempCleanupPlan -Path $Dir -OlderThanDays 2 }
        @($plan).Name | Should -Be 'old.tmp'
    }

    It 'deletes nothing under -WhatIf' {
        $null = Invoke-TempCleanup -Path $dir -WhatIf
        (Get-ChildItem $dir).Count | Should -Be 2
    }

    It 'deletes old files and keeps recent ones' {
        $r = Invoke-TempCleanup -Path $dir -Confirm:$false 6>$null
        $r.Status | Should -Be 'Done'
        (Get-ChildItem $dir).Name | Should -Be 'new.tmp'
    }
}

Describe 'Startup items' {
    It 'decodes StartupApproved values' {
        InModuleScope WinFixKit {
            ConvertFrom-StartupApprovedValue -Value $null | Should -BeTrue
            ConvertFrom-StartupApprovedValue -Value ([byte[]](2, 0, 0, 0)) | Should -BeTrue
            ConvertFrom-StartupApprovedValue -Value ([byte[]](6, 0, 0, 0)) | Should -BeTrue
            ConvertFrom-StartupApprovedValue -Value ([byte[]](3, 0, 0, 0)) | Should -BeFalse
            ConvertFrom-StartupApprovedValue -Value ([byte[]](7, 0, 0, 0)) | Should -BeFalse
        }
    }

    It 'returns well-formed items' {
        foreach ($item in Get-StartupItem) {
            $item.Name | Should -Not -BeNullOrEmpty
            $item.Scope | Should -BeIn 'User', 'Machine'
            $item.Enabled | Should -BeOfType [bool]
        }
    }
}

Describe 'Debloat list' {
    It 'is conservative: never lists core apps' {
        $names = (Get-DebloatCandidate -ListOnly).Name
        $names | Should -Not -BeNullOrEmpty
        foreach ($core in 'Microsoft.WindowsStore', 'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsTerminal', 'Microsoft.ZuneMusic') {
            $names | Should -Not -Contain $core
        }
    }

    It 'rejects apps that are not on the list' {
        { Invoke-Debloat -Name 'Microsoft.WindowsStore' -WhatIf } | Should -Throw '*not on the WinFixKit debloat list*'
    }
}

Describe 'Catalog' {
    It 'points every entry at an exported command with valid parameters' {
        foreach ($item in Get-FixKitCatalog) {
            $cmd = Get-Command $item.Command -Module WinFixKit -ErrorAction Stop
            foreach ($p in $item.Parameters.Keys) { $cmd.Parameters.Keys | Should -Contain $p }
            if ($item.InputParameter) { $cmd.Parameters.Keys | Should -Contain $item.InputParameter }
            if ($item.Destructive) { $item.ReadOnly | Should -BeFalse }
        }
    }

    It 'has unique ids' {
        $ids = (Get-FixKitCatalog).Id
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }
}

Describe 'System snapshot' {
    BeforeAll {
        $script:snap = Get-SystemSnapshot -ErrorHours 1 -MaxEvents 5
    }

    It 'collects every section' {
        foreach ($p in 'System', 'Hardware', 'Disks', 'PhysicalDisks', 'Network', 'RecentErrors') {
            $script:snap.PSObject.Properties.Name | Should -Contain $p
        }
        $script:snap.System.ComputerName | Should -Be $env:COMPUTERNAME
        @($script:snap.Disks).Count | Should -BeGreaterThan 0
    }

    It 'exports HTML, JSON and text reports' {
        foreach ($format in 'Html', 'Json', 'Text') {
            $file = $script:snap | Export-SystemSnapshot -Format $format -Path (Join-Path $TestDrive "snap.$format")
            $file.Length | Should -BeGreaterThan 100
        }
        { Get-Content (Join-Path $TestDrive 'snap.Json') -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'HTML-encodes values and flags low disk space' {
        InModuleScope WinFixKit {
            $fake = [pscustomobject]@{
                GeneratedAt   = Get-Date
                System        = [pscustomobject]@{ ComputerName = '<script>x</script>'; PendingReboot = $true }
                Hardware      = [pscustomobject]@{ Model = 'Test' }
                Disks         = @([pscustomobject]@{ Drive = 'C:'; FreeGB = 3; FreePercent = 4 })
                PhysicalDisks = @()
                Network       = @([pscustomobject]@{ Adapter = 'Ethernet' })
                RecentErrors  = @()
            }
            $html = ConvertTo-SnapshotHtml -Snapshot $fake
            $html | Should -Not -Match '<script>x'
            $html | Should -Match '&lt;script&gt;x'
            $html | Should -Match 'almost full'
            $html | Should -Match 'restart is pending'
        }
    }
}

Describe 'Fix result history' {
    It 'records every step result in FixResults-<date>.jsonl' {
        $null = Reset-NetworkStack -DnsOnly -WhatIf
        $file = InModuleScope WinFixKit { Get-FixKitResultFile }
        $last = Get-Content -LiteralPath $file | Select-Object -Last 1 | ConvertFrom-Json
        $last.Step | Should -Be 'Flush DNS cache'
        $last.Status | Should -Be 'DryRun'
        $last.Computer | Should -Be $env:COMPUTERNAME
    }
}

Describe 'Saved credentials' {
    It 'lists targets without exposing secrets' {
        $creds = @(Get-SavedCredentialTarget)
        foreach ($c in $creds) {
            $c.PSObject.Properties.Name | Should -Not -Contain 'Password'
            $c.Target | Should -Not -BeNullOrEmpty
        }
    }

    It 'refuses patterns that are too broad' {
        { Remove-SavedCredential -Target '*' -WhatIf } | Should -Throw '*too broad*'
        { Remove-SavedCredential -Target 'a*?' -WhatIf } | Should -Throw '*too broad*'
    }

    It 'does nothing when no target matches' {
        $r = Remove-SavedCredential -Target "*winfixkit-no-such-target-$PID*" -WhatIf -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
    }
}

Describe 'Mapped drives' {
    BeforeAll {
        Mock -ModuleName WinFixKit Get-PersistentDriveMapping {
            [pscustomobject]@{ Letter = 'Q'; RemotePath = '\\fs01\share'; UserName = '' }
            [pscustomobject]@{ Letter = 'R'; RemotePath = '\\offline\share'; UserName = '' }
        }
        Mock -ModuleName WinFixKit Test-Path { $false } -ParameterFilter { $LiteralPath -in 'Q:\', 'R:\', '\\offline\share' }
        Mock -ModuleName WinFixKit Test-Path { $true } -ParameterFilter { $LiteralPath -eq '\\fs01\share' }
    }

    It 'plans a reconnect for reachable shares and keeps unreachable mappings' {
        $r = @(Restore-MappedDrive -WhatIf -WarningAction SilentlyContinue)
        ($r | Where-Object Target -like 'Q:*').Status | Should -Be 'DryRun'
        $offline = $r | Where-Object Target -like 'R:*'
        $offline.Status | Should -Be 'Failed'
        $offline.Message | Should -Match 'Mapping kept'
    }

}
