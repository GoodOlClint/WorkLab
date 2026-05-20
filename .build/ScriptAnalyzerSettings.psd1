@{
    Severity    = @('Error', 'Warning')
    ExcludeRules = @(
        # Provider/lifecycle stubs intentionally have no logic yet (Phase 0).
        'PSUseShouldProcessForStateChangingFunctions',
        # PSFramework Write-PSFMessage is our logging surface, not Write-Host.
        'PSAvoidUsingWriteHost'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0', '7.4')
        }
    }
}
