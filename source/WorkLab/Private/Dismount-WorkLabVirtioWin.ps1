function Dismount-WorkLabVirtioWin {
    <#
    .SYNOPSIS
        Dismount the virtio-win.iso. (DISM seam)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue | Out-Null
}
