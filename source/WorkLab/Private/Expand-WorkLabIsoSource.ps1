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
    $WorkDir
}
