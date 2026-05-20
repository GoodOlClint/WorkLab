function New-WorkLabContextFromRecipe {
    <#
    .SYNOPSIS
        Build a LabContext from a lab recipe name + registered provider.
    .DESCRIPTION
        Composes the discovery seam and the provider registry. The lab recipe
        must declare a 'Slug'. This is the single place lifecycle cmdlets turn
        inputs into a LabContext (no per-cmdlet duplication, no module state).
    #>
    [CmdletBinding()]
    [OutputType([LabContext])]
    param(
        [Parameter(Mandatory)][string]$LabRecipe,
        [Parameter(Mandatory)][string]$ProviderName
    )

    $provider = Get-WorkLabProvider -Name $ProviderName  # throws teaching error if absent

    $recipe = Import-WorkLabRecipe -Name $LabRecipe -Type lab
    if (-not $recipe.Data.ContainsKey('Slug')) {
        throw "Lab recipe '$LabRecipe' does not declare a 'Slug'. Add Slug = '<3-12 lowercase alphanumeric>' to the .lab.psd1."
    }

    [LabContext]::new([string]$recipe.Data.Slug, $recipe.Reference, $provider)
}
