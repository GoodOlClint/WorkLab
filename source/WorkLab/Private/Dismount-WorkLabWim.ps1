function Dismount-WorkLabWim {
    <#
    .SYNOPSIS
        Commit (or discard) and unmount a serviced WIM. (DISM seam)
    .DESCRIPTION
        Wraps Dismount-WindowsImage. Saves changes unless -Discard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter()][switch]$Discard
    )

    if ($Discard) {
        Dismount-WindowsImage -Path $MountDir -Discard | Out-Null
    }
    else {
        Dismount-WindowsImage -Path $MountDir -Save | Out-Null
    }
}
