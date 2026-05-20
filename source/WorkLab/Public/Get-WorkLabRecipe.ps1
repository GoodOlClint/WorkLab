function Get-WorkLabRecipe {
    <#
    .SYNOPSIS
        Discover recipes across all recipe sources.

    .DESCRIPTION
        Enumerates lab/topology/component/app recipes from every root returned
        by Resolve-WorkLabRecipePath, in precedence order. Results are
        RecipeReference objects; the same name may appear from multiple
        sources (earlier source = higher precedence for Import-WorkLabRecipe).

    .PARAMETER Name
        Filter to a recipe name. May be namespace-qualified ('NS/name') to
        target a module-shipped recipe specifically.

    .PARAMETER Type
        Filter to a recipe type: lab, topology, component, or app.

    .EXAMPLE
        Get-WorkLabRecipe -Type lab
        Lists all discoverable lab recipes.

    .EXAMPLE
        Get-WorkLabRecipe -Name twoforest
        Returns every reference named 'twoforest', highest precedence first.

    .OUTPUTS
        RecipeReference
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [ValidateSet('lab', 'topology', 'component', 'app')]
        [string]$Type
    )

    $wantNamespace = $null
    $wantName = $Name
    if ($Name -and $Name.Contains('/')) {
        $parts = $Name.Split('/', 2)
        $wantNamespace = $parts[0]
        $wantName = $parts[1]
    }

    $all = foreach ($root in Resolve-WorkLabRecipePath) {
        if (-not $root.Exists) {
            Write-PSFMessage -Level Verbose -Message "Skipping non-existent recipe root: {0}" -StringValues $root.Root
            continue
        }
        Get-WorkLabRecipeFromRoot -Root $root.Root -Source $root.Source -ModuleName $root.ModuleName -Namespace $root.Namespace
    }

    $all | Where-Object {
        $ok = $true
        if ($wantName) { $ok = $ok -and ($_.Name -eq $wantName) }
        if ($wantNamespace) { $ok = $ok -and ($_.Namespace -eq $wantNamespace) }
        if ($Type) { $ok = $ok -and ($_.Type -eq $Type) }
        $ok
    }
}
