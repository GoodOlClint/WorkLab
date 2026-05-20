function Get-WorkLabProviderIso {
    <#
    .SYNOPSIS
        Proxmox provider: list registered ISOs. (REAL)

    .DESCRIPTION
        Lists ISO content in Options.IsoStorage, optionally filtered to one
        file name. Returns normalized objects.

    .PARAMETER Context
        Property bag carrying Options (Server/auth/Node/IsoStorage).

    .PARAMETER Name
        Optional file-name filter.

    .EXAMPLE
        Get-WorkLabProviderIso -Context $c

    .OUTPUTS
        pscustomobject: Provider, Name, VolId, Size, Storage, Raw.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [string]$Name,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Node', 'IsoStorage')
    $session = Connect-WorkLabProxmox -Settings $settings

    Get-WorkLabProxmoxIso -Settings $settings -Session $session -FileName $Name | ForEach-Object {
        [pscustomobject]@{
            Provider = 'Proxmox'
            Name     = (Split-Path -Leaf ($_.VolId -replace ':', '/'))
            VolId    = $_.VolId
            Size     = $_.Size
            Storage  = $settings.IsoStorage
            Raw      = $_
        }
    }
}
