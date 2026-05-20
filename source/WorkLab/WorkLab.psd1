@{
    RootModule        = 'WorkLab.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b3d6c2a1-7e4f-4c2a-9b1d-0a5f6c8e2d31'
    Author            = 'goodolclint'
    CompanyName       = 'goodolclint'
    Copyright         = '(c) goodolclint. All rights reserved.'
    Description       = 'WorkLab framework core: provider-agnostic Windows lab orchestration, recipe discovery seam, secret routing, and structured logging.'
    PowerShellVersion = '7.0'

    RequiredModules   = @('PSFramework')

    FunctionsToExport = @(
        # Lifecycle (Phase 0 stubs)
        'Initialize-Lab'
        'Reset-Lab'
        'Remove-Lab'
        'Get-Lab'
        'Get-LabComputer'
        # Snapshots (Phase 0 stubs)
        'Checkpoint-Lab'
        'Restore-Lab'
        'Get-LabCheckpoint'
        'Remove-LabCheckpoint'
        # Recipe discovery seam (REAL)
        'Get-WorkLabRecipe'
        'Import-WorkLabRecipe'
        'Resolve-WorkLabRecipePath'
        # Provider management (REAL)
        'Register-WorkLabProvider'
        'Get-WorkLabProvider'
        'Test-WorkLabProvider'
        # Image / template management (Phase 2 stubs)
        'Build-WorkLabImage'
        'Get-WorkLabImage'
        'Remove-WorkLabImage'
        # Secrets (REAL)
        'New-WorkLabSecret'
        'Get-WorkLabSecret'
        'Remove-WorkLabSecret'
        # Identity (REAL)
        'Test-WorkLabSlugCollision'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WorkLab', 'Lab', 'Hyper-V', 'Proxmox', 'VMware', 'DSC', 'WindowsServer')
            ProjectUri   = 'https://github.com/goodolclint/WorkLab'
            ReleaseNotes = 'Phase 0: skeleton, discovery seam, provider registry, secret routing, logging, lifecycle stubs.'
        }
    }
}
