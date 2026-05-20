function New-WorkLabProviderContext {
    <#
    .SYNOPSIS
        Build the property-bag Context passed across the provider dispatch seam.
    .DESCRIPTION
        Providers read Options + Slug from a plain bag (no core-class
        coupling). This is the single place core composes that bag.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter()][string]$Slug
    )

    $ctx = @{ Options = $Provider.Options }
    if (-not [string]::IsNullOrWhiteSpace($Slug)) { $ctx['Slug'] = $Slug }
    $ctx
}
