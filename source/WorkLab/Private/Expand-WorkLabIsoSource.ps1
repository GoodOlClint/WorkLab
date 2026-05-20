function Expand-WorkLabIsoSource {
    <#
    .SYNOPSIS
        Copy a source ISO's contents into a writable working directory.
    .DESCRIPTION
        Seam (mocked in unit tests). On Windows this mounts the ISO
        (Mount-DiskImage), copies the tree, then dismounts. Returns the
        working directory path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SourceIso,
        [Parameter(Mandatory)][string]$WorkDir
    )

    $null = New-Item -ItemType Directory -Force -Path $WorkDir
    $image = Mount-DiskImage -ImagePath $SourceIso -PassThru
    try {
        $vol = ($image | Get-Volume).DriveLetter
        Copy-Item -Path "$($vol):\*" -Destination $WorkDir -Recurse -Force
    }
    finally {
        Dismount-DiskImage -ImagePath $SourceIso | Out-Null
    }

    # Files copied from a mounted ISO inherit the source's read-only flag;
    # DISM's Mount-WindowsImage refuses to take a writable mount on a
    # read-only install.wim ("You do not have permissions to mount and modify
    # this image..."). Clear read-only across the extracted tree so DISM can
    # service the WIM and we can write the autounattend + rebuild the ISO.
    Get-ChildItem -LiteralPath $WorkDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object IsReadOnly |
        ForEach-Object { $_.IsReadOnly = $false }

    $WorkDir
}
