function Invoke-FixStep {
    <#
    .SYNOPSIS
        Runs one repair step through the caller's ShouldProcess, logs it, and returns a result object.
    .DESCRIPTION
        Every state-changing action in WinFixKit goes through this function, so -WhatIf, -Confirm
        and logging behave the same everywhere. The step's script block only runs when the caller's
        ShouldProcess approves it. Native commands that set a non-zero exit code mark the step as Failed.
    .OUTPUTS
        WinFixKit.StepResult
    #>
    [CmdletBinding()]
    param(
        # $PSCmdlet of the public function, so -WhatIf/-Confirm apply to that function.
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $description = "$Step ($Target)"
    $reason = [System.Management.Automation.ShouldProcessReason]::None
    $approved = $Cmdlet.ShouldProcess($description, "${description}?", 'WinFixKit', [ref]$reason)

    if (-not $approved) {
        if ($reason -eq [System.Management.Automation.ShouldProcessReason]::WhatIf) {
            Write-FixLog -Message "Would run: $description" -Level DRYRUN
            return New-StepResult -Step $Step -Target $Target -Status 'DryRun' -Message 'Not run (dry run)'
        }
        Write-FixLog -Message "Skipped by user: $description" -Level WARN
        return New-StepResult -Step $Step -Target $Target -Status 'Skipped' -Message 'Declined at confirmation prompt'
    }

    Write-FixLog -Message "Running: $description" -Level ACTION
    $global:LASTEXITCODE = 0
    $lines = [System.Collections.Generic.List[string]]::new()
    try {
        & $ScriptBlock 2>&1 | ForEach-Object {
            # sfc.exe writes UTF-16 that shows up with embedded NULs when captured.
            $text = ("$_" -replace "`0", '').TrimEnd()
            if ($text) {
                $lines.Add($text)
                Write-Information -MessageData $text
            }
        }
        $exitCode = $global:LASTEXITCODE
        $output = ($lines -join [Environment]::NewLine)
        if ($exitCode -ne 0) {
            Write-FixLog -Message "Failed (exit code $exitCode): $description. $output" -Level ERROR
            return New-StepResult -Step $Step -Target $Target -Status 'Failed' -Message "Exit code $exitCode" -Output $output
        }
        Write-FixLog -Message "Done: $description" -Level INFO
        New-StepResult -Step $Step -Target $Target -Status 'Done' -Message 'OK' -Output $output
    }
    catch {
        Write-FixLog -Message "Failed: $description. $($_.Exception.Message)" -Level ERROR
        New-StepResult -Step $Step -Target $Target -Status 'Failed' -Message $_.Exception.Message -Output ($lines -join [Environment]::NewLine)
    }
}

function New-StepResult {
    [CmdletBinding()]
    [OutputType('WinFixKit.StepResult')]
    param(
        [string]$Step,
        [string]$Target,
        [ValidateSet('Done', 'DryRun', 'Skipped', 'Failed')]
        [string]$Status,
        [string]$Message,
        [string]$Output = ''
    )

    [pscustomobject]@{
        PSTypeName = 'WinFixKit.StepResult'
        Time       = Get-Date
        Step       = $Step
        Target     = $Target
        Status     = $Status
        Message    = $Message
        Output     = $Output
    }
}
