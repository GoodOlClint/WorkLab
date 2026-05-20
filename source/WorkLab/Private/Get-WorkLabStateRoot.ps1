function Get-WorkLabStateRoot {
    <#
    .SYNOPSIS
        Resolve the on-disk state root for logs and framework state.
    .DESCRIPTION
        WorkLab only writes to $env:LOCALAPPDATA\WorkLab (Windows) or the
        platform LocalApplicationData equivalent. See docs/DECISIONS.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $base = if ($env:LOCALAPPDATA) {
        $env:LOCALAPPDATA
    }
    else {
        [System.Environment]::GetFolderPath('LocalApplicationData')
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME '.worklab'
    }
    Join-Path $base 'WorkLab'
}
