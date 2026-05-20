function Resolve-WorkLabOscdimg {
    <#
    .SYNOPSIS
        Locate oscdimg.exe (Windows ADK Deployment Tools).
    .DESCRIPTION
        Prefers oscdimg.exe on PATH (common when ADK was added via the
        installer with the "Add to PATH" option, or via an env profile).
        Falls back to the well-known ADK install location, since ADK does
        NOT add itself to PATH by default. Throws a teaching error if
        neither resolves.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $cmd = Get-Command -Name 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) {
        $adkDefault = Join-Path $pf86 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
        if (Test-Path -LiteralPath $adkDefault -PathType Leaf) {
            return $adkDefault
        }
    }

    throw 'oscdimg.exe not found on PATH or in the default ADK location (Program Files (x86)\Windows Kits\10\...\Oscdimg). Install the Windows ADK Deployment Tools feature, then retry.'
}
