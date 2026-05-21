function Get-WorkLabWimIndex {
    <#
    .SYNOPSIS
        Enumerate the image indices in a WIM. (DISM seam)
    .DESCRIPTION
        Wraps Get-WindowsImage to return the integer indices present in a WIM
        (e.g. boot.wim usually has 1 = Windows PE, 2 = Windows Setup). Isolated
        behind this seam so the orchestration is unit-testable cross-platform
        with the real DISM call mocked.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)][string]$WimPath
    )
    [int[]](Get-WindowsImage -ImagePath $WimPath | Sort-Object ImageIndex | Select-Object -ExpandProperty ImageIndex)
}
