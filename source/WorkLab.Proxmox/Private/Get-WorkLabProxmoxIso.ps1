function Get-WorkLabProxmoxIso {
    <#
    .SYNOPSIS
        List ISO storage content, optionally filtered to one file name.
    .DESCRIPTION
        Wraps Get-PveStorageContent (ContentType 'iso'). VolId looks like
        '<storage>:iso/<file>'; matching is by the trailing file name.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Session,
        [Parameter()][string]$FileName
    )

    $items = Get-PveStorageContent -Node $Settings.Node -Storage $Settings.IsoStorage `
        -ContentType 'iso' -Session $Session -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $items = $items | Where-Object {
            $_.VolId -like "*$FileName" -or $_.Volume -eq $FileName -or
            (Split-Path -Leaf ($_.VolId -replace ':', '/')) -eq $FileName
        }
    }
    $items
}
