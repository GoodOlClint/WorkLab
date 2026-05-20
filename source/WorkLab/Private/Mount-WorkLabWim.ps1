function Mount-WorkLabWim {
    <#
    .SYNOPSIS
        Mount an install.wim edition for servicing. (DISM seam)
    .DESCRIPTION
        Wraps Mount-WindowsImage. Edition may be an integer index or an
        edition name. Returns the mount directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WimPath,
        [Parameter(Mandatory)][string]$Edition,
        [Parameter(Mandatory)][string]$MountDir
    )

    $null = New-Item -ItemType Directory -Force -Path $MountDir

    # Defensive: DISM refuses to take a writable mount on a read-only WIM
    # (common when the WIM was copied from a mounted ISO). Expand-WorkLabIsoSource
    # already strips read-only across the extracted tree; this guard makes the
    # cmdlet safe to call directly on any caller-supplied WIM too.
    $wimItem = Get-Item -LiteralPath $WimPath -ErrorAction SilentlyContinue
    if ($wimItem -and $wimItem.IsReadOnly) { $wimItem.IsReadOnly = $false }

    $params = @{ ImagePath = $WimPath; Path = $MountDir }
    if ($Edition -match '^\d+$') { $params['Index'] = [int]$Edition } else { $params['Name'] = $Edition }
    Mount-WindowsImage @params | Out-Null
    $MountDir
}
