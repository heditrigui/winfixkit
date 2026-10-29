function Invoke-TempCleanup {
    <#
    .SYNOPSIS
        Deletes old temporary files and, optionally, cleans the Windows component store.
    .DESCRIPTION
        Removes files older than -OlderThanDays from the user's %TEMP% folder. Recent files are
        kept because running programs may still use them; locked files are skipped.
          -IncludeSystem   also cleans %SystemRoot%\Temp (admin)
          -ComponentStore  runs DISM /StartComponentCleanup to drop superseded updates (admin)
          -Path            cleans extra folders you name
        Without -IncludeSystem or -ComponentStore no admin rights are needed.
    .EXAMPLE
        Invoke-TempCleanup -WhatIf
        Shows how many files and how much space would be freed.
    .EXAMPLE
        Invoke-TempCleanup -IncludeSystem -ComponentStore -OlderThanDays 7
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WinFixKit.StepResult')]
    param(
        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 2,

        [switch]$IncludeSystem,

        [switch]$ComponentStore,

        # Extra folders to clean. Replaces the default user %TEMP% target when given.
        [string[]]$Path
    )

    Write-FixLog -Message "Invoke-TempCleanup started (OlderThanDays=$OlderThanDays, IncludeSystem=$IncludeSystem, ComponentStore=$ComponentStore, WhatIf=$WhatIfPreference)"
    if ($IncludeSystem -or $ComponentStore) {
        Assert-FixKitElevation -FixName 'Invoke-TempCleanup -IncludeSystem/-ComponentStore' -DryRun $WhatIfPreference
    }

    $targets = @(if ($Path) { $Path } else { [IO.Path]::GetTempPath() })
    if ($IncludeSystem) { $targets += Join-Path $env:SystemRoot 'Temp' }

    foreach ($folder in $targets) {
        $plan = @(Get-TempCleanupPlan -Path $folder -OlderThanDays $OlderThanDays)
        $bytes = 0
        foreach ($f in $plan) { $bytes += $f.Length }
        $sizeMB = [math]::Round($bytes / 1MB, 1)
        Invoke-FixStep -Cmdlet $PSCmdlet -Step "Delete $($plan.Count) file(s), $sizeMB MB" -Target $folder -ScriptBlock {
            $removed = 0; $freed = 0; $locked = 0
            foreach ($file in $plan) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop -Confirm:$false
                    $removed++; $freed += $file.Length
                }
                catch { $locked++ }
            }
            'Removed {0} file(s), freed {1:N1} MB, skipped {2} in use.' -f $removed, ($freed / 1MB), $locked
        }
    }

    if ($ComponentStore) {
        Invoke-FixStep -Cmdlet $PSCmdlet -Step 'DISM StartComponentCleanup' -Target 'WinSxS component store' -ScriptBlock {
            dism.exe /Online /Cleanup-Image /StartComponentCleanup
        }
    }
}

function Get-TempCleanupPlan {
    <#
    .SYNOPSIS
        Lists the files Invoke-TempCleanup would delete from one folder. Read-only.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$OlderThanDays = 2
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff }
}
