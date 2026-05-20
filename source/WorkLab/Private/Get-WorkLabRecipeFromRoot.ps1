function Get-WorkLabRecipeFromRoot {
    <#
    .SYNOPSIS
        Enumerate recipe references under a single recipe root directory.
    .DESCRIPTION
        Recognized layout under <root>:
          labs/*.lab.psd1             -> type 'lab'
          topologies/*.topology.psd1  -> type 'topology'
          components/*.component.psd1 -> type 'component'
          apps/<App>/<App>.psd1(+psm1)-> type 'app'
    #>
    [CmdletBinding()]
    [OutputType([RecipeReference])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('InTree', 'SideLoaded', 'Module')][string]$Source,
        [Parameter()][string]$ModuleName,
        [Parameter()][string]$Namespace
    )

    $map = @(
        @{ Sub = 'labs';        Glob = '*.lab.psd1';       Type = 'lab';       Strip = '.lab.psd1' }
        @{ Sub = 'topologies';  Glob = '*.topology.psd1';  Type = 'topology';  Strip = '.topology.psd1' }
        @{ Sub = 'components';  Glob = '*.component.psd1';  Type = 'component'; Strip = '.component.psd1' }
    )

    foreach ($entry in $map) {
        $dir = Join-Path $Root $entry.Sub
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter $entry.Glob -File -ErrorAction SilentlyContinue) {
            $name = $file.Name.Substring(0, $file.Name.Length - $entry.Strip.Length)
            $ref = [RecipeReference]::new($name, $entry.Type, $file.FullName, $Source)
            $ref.ModuleName = $ModuleName
            $ref.Namespace = $Namespace
            $ref
        }
    }

    $appsDir = Join-Path $Root 'apps'
    if (Test-Path -LiteralPath $appsDir -PathType Container) {
        foreach ($appDir in Get-ChildItem -LiteralPath $appsDir -Directory -ErrorAction SilentlyContinue) {
            $manifest = Join-Path $appDir.FullName "$($appDir.Name).psd1"
            $script = Join-Path $appDir.FullName "$($appDir.Name).psm1"
            if ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $script)) {
                $ref = [RecipeReference]::new($appDir.Name, 'app', $manifest, $Source)
                $ref.ModuleName = $ModuleName
                $ref.Namespace = $Namespace
                $ref
            }
            else {
                Write-PSFMessage -Level Warning -Message "App recipe folder '{0}' is missing its .psd1/.psm1 pair; skipping." -StringValues $appDir.FullName
            }
        }
    }
}
