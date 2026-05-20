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
    $params = @{ ImagePath = $WimPath; Path = $MountDir }
    if ($Edition -match '^\d+$') { $params['Index'] = [int]$Edition } else { $params['Name'] = $Edition }
    Mount-WindowsImage @params | Out-Null
    $MountDir
}
