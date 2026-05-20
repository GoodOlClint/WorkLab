function Add-WorkLabWimContent {
    <#
    .SYNOPSIS
        Inject drivers and/or update packages into a mounted WIM. (DISM seam)
    .DESCRIPTION
        Wraps Add-WindowsDriver (recurse a driver folder) and
        Add-WindowsPackage (each .msu/.cab under an update folder). Missing
        or empty source folders are a no-op.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter()][string]$DriverPath,
        [Parameter()][string]$UpdatePath
    )

    if ($DriverPath -and (Test-Path -LiteralPath $DriverPath -PathType Container)) {
        Add-WindowsDriver -Path $MountDir -Driver $DriverPath -Recurse | Out-Null
    }
    if ($UpdatePath -and (Test-Path -LiteralPath $UpdatePath -PathType Container)) {
        Get-ChildItem -LiteralPath $UpdatePath -Include '*.msu', '*.cab' -File -Recurse |
            ForEach-Object { Add-WindowsPackage -Path $MountDir -PackagePath $_.FullName | Out-Null }
    }
}
