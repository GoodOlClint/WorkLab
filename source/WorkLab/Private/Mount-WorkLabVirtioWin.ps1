function Mount-WorkLabVirtioWin {
    <#
    .SYNOPSIS
        Mount the virtio-win.iso and return the staged asset paths. (DISM seam)
    .DESCRIPTION
        Locates the driver tree (amd64 root, recursive Add-WindowsDriver will
        filter) and the qemu-guest-agent MSI. Filename has shifted between
        virtio-win releases ('qemu-ga-x86_64.msi' on recent stable, plain
        'qemu-ga.msi' on older builds) so both globs are tried.

        Paired with Dismount-WorkLabVirtioWin in a try/finally by callers.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $image = Mount-DiskImage -ImagePath $Path -PassThru
    $vol = "$(($image | Get-Volume).DriveLetter):"

    $driverPath = Join-Path $vol 'amd64'
    if (-not (Test-Path -LiteralPath $driverPath -PathType Container)) {
        Dismount-DiskImage -ImagePath $Path | Out-Null
        throw "virtio-win.iso layout unexpected: no amd64 driver folder under $vol\."
    }

    $msi = Get-ChildItem -LiteralPath (Join-Path $vol 'guest-agent') `
        -Filter 'qemu-ga*.msi' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'qemu-ga-x86_64.msi' -or $_.Name -eq 'qemu-ga.msi' } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $msi) {
        Dismount-DiskImage -ImagePath $Path | Out-Null
        throw "virtio-win.iso: no qemu-ga MSI found under $vol\guest-agent (looked for qemu-ga-x86_64.msi, qemu-ga.msi)."
    }

    [pscustomobject]@{
        Volume       = $vol
        DriverPath   = $driverPath
        AgentMsiPath = $msi.FullName
    }
}
