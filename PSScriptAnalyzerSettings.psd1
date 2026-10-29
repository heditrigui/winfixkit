@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Public fixes delegate ShouldProcess to the private Invoke-FixStep helper by passing their
        # $PSCmdlet, so -WhatIf/-Confirm work but this rule cannot see the call and misfires.
        'PSShouldProcess'
        # Fires on private helpers that only build objects or GUI controls (New-StepResult,
        # New-FixKitWindow, ...). Every public fix that changes the system is required to support
        # -WhatIf/-Confirm by the "Safety contract" tests instead.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
