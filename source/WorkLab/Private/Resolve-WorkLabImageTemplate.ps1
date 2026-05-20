function Resolve-WorkLabImageTemplate {
    <#
    .SYNOPSIS
        Return the provider template for an image, or $null (hybrid-cache check).
    .DESCRIPTION
        Templates are named lab-<buildslug>-tpl01. A hit means the sysprepped
        template already exists and a rebuild is unnecessary.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][string]$ImageName
    )

    $slug = Get-WorkLabImageBuildSlug -Name $ImageName
    $tplName = "lab-$slug-tpl01"
    $ctx = @{ Options = $Provider.Options; Slug = $slug }

    $tpl = Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Get' -Noun 'Template' `
        -Arguments @{ Context = $ctx; Name = $tplName } |
        Select-Object -First 1

    if ($tpl) {
        $tpl | Add-Member -NotePropertyName TemplateName -NotePropertyValue $tplName -Force -PassThru
    }
}
