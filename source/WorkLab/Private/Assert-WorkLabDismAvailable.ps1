function Assert-WorkLabDismAvailable {
    <#
    .SYNOPSIS
        Fast-fail unless DISM image servicing is usable (Windows-only).
    .DESCRIPTION
        The WIM-patching pipeline uses the DISM PowerShell module and the
        Windows ADK oscdimg for ISO rebuild. Both are Windows-only. On any
        other platform Build-WorkLabImage cannot run; this throws a teaching
        error rather than failing obscurely later. See docs/DECISIONS.md.
    #>
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw 'Build-WorkLabImage requires a Windows host: DISM image servicing and ADK oscdimg are Windows-only. Run it on Windows (or a Windows build worker). On non-Windows this is expected to fail fast.'
    }
    if (-not (Get-Command -Name Mount-WindowsImage -ErrorAction SilentlyContinue)) {
        throw 'The DISM PowerShell module (Mount-WindowsImage) is not available. Install the Windows DISM/ADK components, then retry Build-WorkLabImage.'
    }
}
