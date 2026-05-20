function Resolve-WorkLabInTreeRecipeRoot {
    <#
    .SYNOPSIS
        Locate the in-tree recipes/ directory relative to the module.
    .DESCRIPTION
        Primary: <module path>/../recipes (the packaged/installed layout where
        recipes ship alongside the module). Fallback: walk ancestors of the
        module base looking for a 'recipes' directory — this is the monorepo
        dev layout where source/WorkLab and recipes/ are repo-root siblings.
        Returns $null if none found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$ModuleRoot = $script:WorkLabModuleRoot,

        [Parameter()]
        [int]$MaxAncestorDepth = 5
    )

    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        return $null
    }

    $primary = Join-Path (Split-Path $ModuleRoot -Parent) 'recipes'
    if (Test-Path -LiteralPath $primary -PathType Container) {
        return (Resolve-Path -LiteralPath $primary).Path
    }

    $cursor = $ModuleRoot
    for ($i = 0; $i -lt $MaxAncestorDepth; $i++) {
        $cursor = Split-Path $cursor -Parent
        if ([string]::IsNullOrWhiteSpace($cursor)) { break }
        $candidate = Join-Path $cursor 'recipes'
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}
