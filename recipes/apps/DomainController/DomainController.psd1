@{
    RootModule        = 'DomainController.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'e5a6b7c8-9d0f-4ab1-bc3d-4e5f6a7b8c9d'
    Author            = 'goodolclint'
    Description       = 'WorkLab app recipe: domain controller promotion (Phase 0 contract reference).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Install-WorkLabAppRecipe')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('WorkLab', 'WorkLabRecipe', 'AppRecipe')
        }
        # An installed module shipping recipes declares this so the discovery
        # seam can find them (see docs/RECIPES.md, source 3).
        WorkLab = @{
            RecipeRoot = 'recipes'
        }
    }
}
