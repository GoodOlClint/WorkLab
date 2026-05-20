function Resolve-WorkLabRecipePath {
    <#
    .SYNOPSIS
        Resolve the ordered set of recipe root directories.

    .DESCRIPTION
        Returns recipe roots in discovery precedence:
          1. In-tree    — recipes/ shipped with / beside the WorkLab module.
          2. Side-loaded — paths in $env:WORKLAB_RECIPE_PATH (platform-separated).
          3. Module      — installed modules tagged 'WorkLabRecipe' whose
                            manifest declares PrivateData.WorkLab.RecipeRoot.

        Earlier sources win on name collisions. Namespace-qualify a module
        recipe to override (e.g. 'Semperis.WorkLab.Recipes/dsp-install').

    .EXAMPLE
        Resolve-WorkLabRecipePath
        Lists every recipe root with its source and existence flag.

    .OUTPUTS
        pscustomobject with Source, Root, ModuleName, Namespace, Exists.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # 1. In-tree
    $inTree = Resolve-WorkLabInTreeRecipeRoot
    if ($inTree) {
        [pscustomobject]@{
            Source     = 'InTree'
            Root       = $inTree
            ModuleName = $null
            Namespace  = $null
            Exists     = $true
        }
    }
    else {
        Write-PSFMessage -Level Verbose -Message 'No in-tree recipes/ directory resolved.'
    }

    # 2. Side-loaded
    if (-not [string]::IsNullOrWhiteSpace($env:WORKLAB_RECIPE_PATH)) {
        $sep = [System.IO.Path]::PathSeparator
        foreach ($p in ($env:WORKLAB_RECIPE_PATH -split [regex]::Escape($sep))) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            $exists = Test-Path -LiteralPath $p -PathType Container
            [pscustomobject]@{
                Source     = 'SideLoaded'
                Root       = $p
                ModuleName = $null
                Namespace  = $null
                Exists     = $exists
            }
        }
    }

    # 3. Installed modules tagged WorkLabRecipe
    foreach ($src in Get-WorkLabModuleRecipeSource) {
        [pscustomobject]@{
            Source     = 'Module'
            Root       = $src.Root
            ModuleName = $src.ModuleName
            Namespace  = $src.Namespace
            Exists     = $true
        }
    }
}
