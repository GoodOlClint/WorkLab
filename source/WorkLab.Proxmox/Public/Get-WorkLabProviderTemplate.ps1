function Get-WorkLabProviderTemplate {
    <#
    .SYNOPSIS
        Proxmox provider: list templates. (REAL)

    .DESCRIPTION
        Lists Proxmox templates. With -Name, returns the one template by
        name; otherwise all templates (optionally narrowed to lab-<slug>-*
        when Context.Slug is present).

    .PARAMETER Context
        Property bag with Options (Server/auth/Node) and optional Slug.

    .PARAMETER Name
        Template name filter (a WorkLab VM name).

    .EXAMPLE
        Get-WorkLabProviderTemplate -Context $c

    .OUTPUTS
        pscustomobject normalized template(s).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter()][string]$Name,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Node')
    $session = Connect-WorkLabProxmox -Settings $settings

    $templates = Get-PveVm -Session $session -TemplatesOnly -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $templates = $templates | Where-Object { $_.Name -eq $Name }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($settings.Slug)) {
        $templates = $templates | Where-Object { $_.Name -like "lab-$($settings.Slug)-*" }
    }

    $templates | ForEach-Object {
        ConvertTo-WorkLabProxmoxVm -Vm $_ -Node $settings.Node |
            Add-Member -NotePropertyName IsTemplate -NotePropertyValue $true -PassThru
    }
}
