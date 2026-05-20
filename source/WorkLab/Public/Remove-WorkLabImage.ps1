function Remove-WorkLabImage {
    <#
    .SYNOPSIS
        Delete a cached WorkLab image/template. (REAL, idempotent)

    .DESCRIPTION
        Removes <cache root>/images/<name>/ (patched ISO + manifest).
        Idempotent: a missing image is a no-op.

    .PARAMETER Name
        Image name to remove.

    .EXAMPLE
        Remove-WorkLabImage -Name ws2025-core

    .OUTPUTS
        pscustomobject: Name, Removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $dir = Join-Path (Get-WorkLabImageRoot) $Name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-PSFMessage -Level Verbose -Message "Image '{0}' not in cache; nothing to remove." -StringValues $Name
        return [pscustomobject]@{ Name = $Name; Removed = $false }
    }

    if ($PSCmdlet.ShouldProcess($dir, 'Remove image from cache')) {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
        Write-PSFMessage -Level Significant -Message "Removed image '{0}' from cache." -StringValues $Name
        return [pscustomobject]@{ Name = $Name; Removed = $true }
    }
}
