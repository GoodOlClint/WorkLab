@{
    Severity    = @('Error', 'Warning')
    ExcludeRules = @(
        # Provider/lifecycle stubs intentionally have no logic yet (Phase 0).
        'PSUseShouldProcessForStateChangingFunctions',
        # PSFramework Write-PSFMessage is our logging surface, not Write-Host.
        'PSAvoidUsingWriteHost',
        # Disabled: this rule NullReferenceExceptions on the windows-latest
        # runner (PSScriptAnalyzer 1.25.0 / pwsh 7.x) when scanning the
        # full source tree. Same code analyzes clean on Ubuntu and on a
        # local Win11 VM with the same PSSA version. Track upstream and
        # re-enable when the regression is fixed; we rely on parse-checks
        # + Pester to catch the script-compatibility issues this rule
        # would have caught.
        'PSUseCompatibleSyntax'
    )
}
