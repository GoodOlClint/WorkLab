function New-WorkLabBootableIso {
    <#
    .SYNOPSIS
        Rebuild a bootable ISO from a working directory. (oscdimg seam)
    .DESCRIPTION
        Wraps the Windows ADK oscdimg.exe (BIOS + UEFI El Torito boot).
        Returns the produced ISO path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$IsoPath
    )

    $oscdimg = Resolve-WorkLabOscdimg

    $bios = Join-Path $WorkDir 'boot/etfsboot.com'
    $uefi = Join-Path $WorkDir 'efi/microsoft/boot/efisys.bin'
    $bootData = '2#p0,e,b{0}#pEF,e,b{1}' -f $bios, $uefi

    & $oscdimg '-m' '-o' '-u2' '-udfver102' "-bootdata:$bootData" $WorkDir $IsoPath
    if ($LASTEXITCODE -ne 0) {
        throw "oscdimg failed (exit $LASTEXITCODE) building $IsoPath."
    }
    $IsoPath
}
