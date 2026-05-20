@{
    RootModule        = 'WorkLab.Proxmox.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1c2e3f4-5b6d-4789-9a0b-1c2d3e4f5a6b'
    Author            = 'goodolclint'
    CompanyName       = 'goodolclint'
    Copyright         = '(c) goodolclint. All rights reserved.'
    Description       = 'WorkLab Proxmox provider. Phase 0: REAL per-lab SDN network ops + health check; remaining contract stubbed (Phase 1).'
    PowerShellVersion = '7.0'

    # PSProxmoxVE is required at runtime for the REAL cmdlets but is NOT a hard
    # import dependency: cmdlets fail fast with a teaching message if absent,
    # so the module still imports for contract inspection.
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
        # Phase 2.5 guest channel
        'Test-WorkLabProviderGuestAgent'
        'Invoke-WorkLabProviderGuestCommand'
        'Write-WorkLabProviderGuestFile'
        'Read-WorkLabProviderGuestFile'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags                       = @('WorkLab', 'Provider', 'Proxmox')
            ProjectUri                 = 'https://github.com/goodolclint/WorkLab'
            ReleaseNotes               = 'Phase 0: REAL SDN network ops + Test; rest NotImplemented (Phase 1).'
            ExternalModuleDependencies = @('PSProxmoxVE')
        }
    }
}
