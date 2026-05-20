@{
    RootModule           = 'WorkLabDsc.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'd1f2a3b4-5c6d-4e7f-8a9b-0c1d2e3f4a5b'
    Author               = 'goodolclint'
    CompanyName          = 'goodolclint'
    Copyright            = '(c) goodolclint. All rights reserved.'
    Description          = 'WorkLab custom DSC composite resources (empty in Phase 0; composites land Phase 5+).'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    DscResourcesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('WorkLab', 'DSC')
            ProjectUri   = 'https://github.com/goodolclint/WorkLab'
            ReleaseNotes = 'Phase 0: empty skeleton.'
        }
    }
}
