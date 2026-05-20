function Get-WorkLabImage {
    <#
    .SYNOPSIS
        List cached WorkLab images/templates. (REAL)

    .DESCRIPTION
        Enumerates images in the cache (<cache root>/images/<name>/), reading
        each <name>.image.json manifest. Cross-platform (filesystem only).

    .PARAMETER Name
        Optional image-name filter.

    .EXAMPLE
        Get-WorkLabImage

    .EXAMPLE
        Get-WorkLabImage -Name ws2025-core

    .OUTPUTS
        pscustomobject: Name, IsoPath, SizeBytes, Manifest.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    $root = Get-WorkLabImageRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-PSFMessage -Level Verbose -Message 'No image cache root yet: {0}' -StringValues $root
        return
    }

    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($Name -and $_.Name -ne $Name) { return }
        $manifest = Read-WorkLabImageManifest -Name $_.Name
        if (-not $manifest) {
            Write-PSFMessage -Level Verbose -Message 'Skipping image folder without manifest: {0}' -StringValues $_.Name
            return
        }
        $isoPath = if ($manifest.isoFile) { $manifest.isoFile } else { Join-Path $_.FullName "$($_.Name).iso" }
        $size = if (Test-Path -LiteralPath $isoPath -PathType Leaf) { (Get-Item -LiteralPath $isoPath).Length } else { $null }
        [pscustomobject]@{
            Name      = $_.Name
            IsoPath   = $isoPath
            SizeBytes = $size
            Manifest  = $manifest
        }
    }
}
