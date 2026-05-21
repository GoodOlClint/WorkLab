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
    # Use the ADK's no-prompt UEFI boot image so the unattended CD boot does NOT
    # wait for "Press any key to boot from CD or DVD" — that prompt (baked into
    # the media's efisys.bin) requires a keystroke nobody is there to press, so
    # the install VM never boots Setup and the build hangs. The Windows media
    # only ships the prompting efisys.bin; the ADK ships efisys_noprompt.bin
    # next to oscdimg.exe. Fall back to the media's efisys.bin if the no-prompt
    # variant isn't found.
    $uefiNoPrompt = Join-Path (Split-Path -Parent $oscdimg) 'efisys_noprompt.bin'
    $uefi = if (Test-Path -LiteralPath $uefiNoPrompt) {
        $uefiNoPrompt
    }
    else {
        Join-Path $WorkDir 'efi/microsoft/boot/efisys.bin'
    }
    $bootData = '2#p0,e,b{0}#pEF,e,b{1}' -f $bios, $uefi

    & $oscdimg '-m' '-o' '-u2' '-udfver102' "-bootdata:$bootData" $WorkDir $IsoPath
    if ($LASTEXITCODE -ne 0) {
        throw "oscdimg failed (exit $LASTEXITCODE) building $IsoPath."
    }
    $IsoPath
}
