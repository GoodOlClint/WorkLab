function Write-WorkLabImageManifest {
    <#
    .SYNOPSIS
        Write an image manifest to <image root>/<name>/<name>.image.json.
    .DESCRIPTION
        Creates the per-image folder if needed. Returns the manifest path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Manifest
    )

    $dir = Join-Path (Get-WorkLabImageRoot) $Name
    $null = New-Item -ItemType Directory -Force -Path $dir
    $path = Join-Path $dir "$Name.image.json"
    if ($PSCmdlet.ShouldProcess($path, 'Write image manifest')) {
        $Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    }
    $path
}
