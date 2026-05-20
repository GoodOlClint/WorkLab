function New-WorkLabSecretPath {
    <#
    .SYNOPSIS
        Build a namespaced secret name: worklab/<slug>/<role>/<name>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Name
    )

    [LabContext]::AssertValidSlug($Slug)
    foreach ($pair in @(@{ v = $Role; n = 'Role' }, @{ v = $Name; n = 'Name' })) {
        if ([string]::IsNullOrWhiteSpace($pair.v) -or $pair.v -match '[/\\]') {
            throw [System.ArgumentException]::new("Secret $($pair.n) '$($pair.v)' must be non-empty and contain no slashes.")
        }
    }
    'worklab/{0}/{1}/{2}' -f $Slug, $Role, $Name
}
