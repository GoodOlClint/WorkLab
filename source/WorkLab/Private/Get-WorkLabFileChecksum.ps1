function Get-WorkLabFileChecksum {
    <#
    .SYNOPSIS
        SHA256 of a file (lowercase hex), or $null if it does not exist.
    .DESCRIPTION
        Used to record/verify source and produced ISO integrity in image
        manifests. Cross-platform (Get-FileHash).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
