function Mount-WorkLabVirtioWin {
    <#
    .SYNOPSIS
        Mount the virtio-win.iso and return the staged asset paths. (DISM seam)
    .DESCRIPTION
        Locates three assets on the virtio-win ISO:
          - DriverPath: the \amd64 root, which holds ONLY the storage drivers
            (viostor/vioscsi) per OS version. These are the boot-critical drivers
            and the only ones we offline-inject (see Build-WorkLabImage) -- the
            disk must be visible before Setup and at first boot.
          - DriverMsiPath: virtio-win-gt-x64.msi at the ISO root, the vendor
            driver installer run online at FirstLogon (pre-sysprep) to install
            the non-storage drivers (vioser/NetKVM/balloon/...). It does the
            arch/OS matching that a recursive offline DISM inject cannot (the
            per-driver tree mixes amd64/x86/ARM64, which makes Add-WindowsDriver
            -Recurse from the root fail with "parameter is incorrect").
          - AgentMsiPath: the qemu-guest-agent MSI. Filename has shifted between
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

    $driverMsi = Get-ChildItem -LiteralPath $vol -Filter 'virtio-win-gt-x64.msi' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $driverMsi) {
        Dismount-DiskImage -ImagePath $Path | Out-Null
        throw "virtio-win.iso: no virtio-win-gt-x64.msi found at $vol\."
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
        Volume        = $vol
        DriverPath    = $driverPath
        DriverMsiPath = $driverMsi.FullName
        AgentMsiPath  = $msi.FullName
    }
}
