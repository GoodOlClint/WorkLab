@{
    RootModule        = 'WorkLab.HyperV.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b2d3f4a5-6c7e-489a-ab1c-2d3e4f5a6b7c'
    Author            = 'goodolclint'
    CompanyName       = 'goodolclint'
    Copyright         = '(c) goodolclint. All rights reserved.'
    Description       = 'WorkLab Hyper-V provider. Phase 0: full contract stubbed (NotImplementedException); implementation lands Phase 7.'
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
            Tags         = @('WorkLab', 'Provider', 'Hyper-V')
            ProjectUri   = 'https://github.com/goodolclint/WorkLab'
            ReleaseNotes = 'Phase 0: contract stubbed; implementation Phase 7.'
        }
    }
}
