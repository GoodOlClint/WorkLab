function Get-WorkLabCacheRoot {
    <#
    .SYNOPSIS
        Resolve the cache root for templates and patched ISOs.
    .DESCRIPTION
        Honors $env:WORKLAB_CACHE_PATH, defaulting to ~/.worklab/cache.
        WorkLab writes large artifacts only here. See docs/DECISIONS.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:WORKLAB_CACHE_PATH) {
        return $env:WORKLAB_CACHE_PATH
    }
    Join-Path $HOME '.worklab/cache'
}
