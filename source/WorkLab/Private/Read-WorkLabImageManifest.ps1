function Read-WorkLabImageManifest {
    <#
    .SYNOPSIS
        Read an image manifest (<image root>/<name>/<name>.image.json).
    .DESCRIPTION
        Returns the parsed manifest object, or $null if the image is not in
        the cache.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $path = Join-Path (Get-WorkLabImageRoot) "$Name/$Name.image.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
