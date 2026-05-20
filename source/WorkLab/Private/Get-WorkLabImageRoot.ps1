function Get-WorkLabImageRoot {
    <#
    .SYNOPSIS
        Resolve the image cache root: <cache root>/images.
    .DESCRIPTION
        Patched ISOs and their manifests live under here, one folder per
        image name. Honors $env:WORKLAB_CACHE_PATH via Get-WorkLabCacheRoot.
        See docs/DECISIONS.md (sanctioned write locations).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path (Get-WorkLabCacheRoot) 'images'
}
