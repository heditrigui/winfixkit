function Invoke-FixKitRemote {
    <#
    .SYNOPSIS
        Runs a WinFixKit fix or check on one or more other PCs over PowerShell remoting.
    .DESCRIPTION
        Sends WinFixKit's code with the command (nothing has to be installed on the remote
        PC) and runs it through Invoke-Command. -Fix takes a catalog id (see Get-FixKitCatalog)
        or a WinFixKit command name. Use -WhatIf for a dry run on the remote PC.
        Without -WhatIf you confirm once here, and the fix then runs without prompting on the
        remote side. Remote PCs log to their own WinFixKit log, and this PC logs what was sent where.
        Requires WinRM on the target (Enable-PSRemoting) and, for most fixes, admin rights there.
    .EXAMPLE
        Invoke-FixKitRemote -ComputerName PC042 -Fix diagnose
    .EXAMPLE
        Invoke-FixKitRemote -ComputerName PC042, PC043 -Fix spooler -Credential (Get-Credential) -WhatIf
    .EXAMPLE
        Invoke-FixKitRemote -ComputerName PC042 -Fix Remove-SavedCredential -Parameters @{ Target = '*fileserver*' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        # Catalog id (e.g. 'spooler') or command name (e.g. 'Reset-PrintSpooler').
        [Parameter(Mandatory)]
        [string]$Fix,

        # Extra parameters for the command, e.g. @{ OlderThanDays = 7 }.
        [hashtable]$Parameters = @{},

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [switch]$UseSSL
    )

    $resolved = Resolve-FixKitRemoteCommand -Fix $Fix -Parameters $Parameters
    $command = $resolved.Command
    $splat = $resolved.Parameters
    $supportsWhatIf = $resolved.SupportsShouldProcess

    $dryRun = [bool]$WhatIfPreference
    if ($supportsWhatIf) {
        if ($dryRun) { $splat.WhatIf = $true } else { $splat.Confirm = $false }
    }
    $paramText = ($splat.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '

    $targets = @(foreach ($computer in $ComputerName) {
            if ($dryRun -or -not $supportsWhatIf) { $computer; continue }
            if ($PSCmdlet.ShouldProcess($computer, "Run $command $paramText")) { $computer }
            else { Write-FixLog -Message "Remote: $command on $computer declined at confirmation." -Level WARN }
        })
    if (-not $targets) { return }

    Write-FixLog -Message "Remote: running $command $paramText on $($targets -join ', ') (dry run=$dryRun)" -Level ACTION
    $invokeParams = @{
        ComputerName = $targets
        ScriptBlock  = $script:RemotePayload
        ArgumentList = @((Get-FixKitRemoteModuleCode), $command, $splat)
        ErrorAction  = 'Continue'
    }
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) { $invokeParams.Credential = $Credential }
    if ($UseSSL) { $invokeParams.UseSSL = $true }

    Invoke-Command @invokeParams -ErrorVariable remoteErrors | ForEach-Object {
        if ($_.PSObject.Properties['Status']) {
            Write-FixLog -Message "Remote: $($_.PSComputerName) $($_.Step) ($($_.Target)) = $($_.Status)"
        }
        $_
    }
    foreach ($err in $remoteErrors) {
        Write-FixLog -Message "Remote: $($err.TargetObject) failed: $($err.Exception.Message)" -Level ERROR
    }
}

# Runs on the remote PC: loads WinFixKit as an in-memory module and runs the command.
$script:RemotePayload = {
    param([string]$ModuleCode, [string]$Command, [hashtable]$Parameters)
    $null = New-Module -Name WinFixKit -ScriptBlock ([scriptblock]::Create($ModuleCode))
    & $Command @Parameters
}

# Commands that make no sense remotely (GUI, local files, this function itself).
$script:RemoteBlocked = 'Show-FixKitGui', 'Invoke-FixKitRemote', 'Export-FixKitTicketBundle', 'Export-SystemSnapshot', 'Get-FixKitLogPath', 'Get-FixKitCatalog'

function Resolve-FixKitRemoteCommand {
    <#
    .SYNOPSIS
        Turns a catalog id or command name into the command and parameters to run remotely.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Fix, [hashtable]$Parameters = @{})

    $splat = @{}
    $item = Get-FixKitCatalog | Where-Object Id -eq $Fix
    if ($item) {
        $command = $item.Command
        foreach ($p in $item.Parameters.GetEnumerator()) { $splat[$p.Key] = $p.Value }
        # Snapshots are saved to a file locally; remotely return the data instead.
        if ($command -eq 'Export-SystemSnapshot') { $command = 'Get-SystemSnapshot' }
    }
    else {
        $command = $Fix
    }
    foreach ($p in $Parameters.GetEnumerator()) { $splat[$p.Key] = $p.Value }

    $cmd = Get-Command -Name $command -Module WinFixKit -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "'$Fix' is not a WinFixKit catalog id or command. See Get-FixKitCatalog." }
    if ($command -in $script:RemoteBlocked) { throw "$command cannot be run remotely." }
    foreach ($key in $splat.Keys) {
        if (-not $cmd.Parameters.ContainsKey($key)) { throw "$command has no parameter -$key." }
    }

    [pscustomobject]@{
        Command               = $command
        Parameters            = $splat
        SupportsShouldProcess = $cmd.Parameters.ContainsKey('WhatIf')
    }
}

function Get-FixKitRemoteModuleCode {
    <#
    .SYNOPSIS
        Returns WinFixKit's source as one script for the remote in-memory module (GUI code left out).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = Split-Path $PSScriptRoot -Parent
    $files = @(Get-ChildItem -Path (Join-Path $root 'Private'), (Join-Path $root 'Public') -Filter '*.ps1' -File |
            Where-Object { $_.Name -notin 'Gui.ps1', 'Show-FixKitGui.ps1' } | Sort-Object { $_.Directory.Name -ne 'Private' }, Name)
    $parts = @('Set-StrictMode -Version Latest')
    foreach ($file in $files) { $parts += [IO.File]::ReadAllText($file.FullName) }
    $parts -join [Environment]::NewLine
}
