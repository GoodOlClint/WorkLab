@{
    RootModule        = 'WorkLab.VMware.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c3e4a5b6-7d8f-49ab-bc2d-3e4f5a6b7c8d'
    Author            = 'goodolclint'
    CompanyName       = 'goodolclint'
    Copyright         = '(c) goodolclint. All rights reserved.'
    Description       = 'WorkLab VMware provider. Phase 0: full contract stubbed (NotImplementedException); implementation lands Phase 8.'
    PowerShellVersion = '7.0'
    RequiredModules   = @()

    FunctionsToExport = @(
        'Test-WorkLabProviderConnection'
        'New-WorkLabProviderNetwork'
        'Remove-WorkLabProviderNetwork'
        'Get-WorkLabProviderNetwork'
        'New-WorkLabProviderIso'
        'Get-WorkLabProviderIso'
        'Remove-WorkLabProviderIso'
        'Export-WorkLabProviderTemplate'
        'Get-WorkLabProviderTemplate'
        'Remove-WorkLabProviderTemplate'
        'New-WorkLabProviderVm'
        'Copy-WorkLabProviderVm'
        'Get-WorkLabProviderVm'
        'Start-WorkLabProviderVm'
        'Stop-WorkLabProviderVm'
        'Remove-WorkLabProviderVm'
        'Checkpoint-WorkLabProviderVm'
        'Restore-WorkLabProviderVm'
        'Get-WorkLabProviderCheckpoint'
        'Remove-WorkLabProviderCheckpoint'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WorkLab', 'Provider', 'VMware')
            ProjectUri   = 'https://github.com/goodolclint/WorkLab'
            ReleaseNotes = 'Phase 0: contract stubbed; implementation Phase 8.'
        }
    }
}
