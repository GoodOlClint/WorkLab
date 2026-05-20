function Get-WorkLabModuleRecipeSource {
    <#
    .SYNOPSIS
        Discover installed modules that ship WorkLab recipes.
    .DESCRIPTION
        Scans available modules for a manifest whose
        PrivateData.PSData.Tags contains 'WorkLabRecipe'. The recipe root is
        <ModuleBase>/<PrivateData.WorkLab.RecipeRoot>. The module name is used
        as the collision namespace.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    foreach ($mod in Get-Module -ListAvailable -ErrorAction SilentlyContinue) {
        $priv = $mod.PrivateData
        if ($priv -isnot [hashtable]) { continue }

        $tags = $null
        if ($priv['PSData'] -is [hashtable]) {
            $tags = $priv['PSData']['Tags']
        }
        if (-not $tags -or ($tags -notcontains 'WorkLabRecipe')) { continue }

        $recipeRootRel = $null
        if ($priv['WorkLab'] -is [hashtable]) {
            $recipeRootRel = $priv['WorkLab']['RecipeRoot']
        }
        if ([string]::IsNullOrWhiteSpace($recipeRootRel)) {
            Write-PSFMessage -Level Warning -Message "Module {0} is tagged WorkLabRecipe but has no PrivateData.WorkLab.RecipeRoot; skipping." -StringValues $mod.Name
            continue
        }

        $root = Join-Path $mod.ModuleBase $recipeRootRel
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Write-PSFMessage -Level Warning -Message "Module {0} RecipeRoot '{1}' does not exist; skipping." -StringValues $mod.Name, $recipeRootRel
            continue
        }

        [pscustomobject]@{
            ModuleName = $mod.Name
            Namespace  = $mod.Name
            Root       = (Resolve-Path -LiteralPath $root).Path
        }
    }
}
