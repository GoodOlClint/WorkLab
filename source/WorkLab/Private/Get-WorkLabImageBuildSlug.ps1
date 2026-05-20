function Get-WorkLabImageBuildSlug {
    <#
    .SYNOPSIS
        Deterministic, throwaway build slug for an image's ephemeral network.
    .DESCRIPTION
        The image-build (install) VM is not lab-scoped; it runs on an
        ephemeral per-image SDN VNet that is torn down after templating. The
        slug is 'imgb' + 8 base36 chars of sha256(name) -> 12 chars, valid
        per the slug rule (^[a-z0-9]{3,12}$). Deterministic so a re-run
        reconciles the same ephemeral network.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name.ToLowerInvariant()))
    }
    finally {
        $sha.Dispose()
    }

    $big = [System.Numerics.BigInteger]::Abs([System.Numerics.BigInteger]::new($bytes[0..15] + [byte]0))
    $alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    $sb = [System.Text.StringBuilder]::new()
    while ($big -gt 0 -and $sb.Length -lt 8) {
        [void]$sb.Insert(0, $alphabet[[int]($big % 36)])
        $big = [System.Numerics.BigInteger]::Divide($big, 36)
    }
    'imgb' + $sb.ToString().PadLeft(8, '0')
}
