function Import-WorkLabRecipe {
    <#
    .SYNOPSIS
        Resolve and load a single recipe by name.

    .DESCRIPTION
        Picks the highest-precedence recipe matching Name (unless the name is
        namespace-qualified, which targets a specific module source). psd1
        recipes (lab/topology/component) are returned as parsed data. App
        recipes are imported as modules and validated to export
        Install-WorkLabAppRecipe with the required signature.

    .PARAMETER Name
        Recipe name, optionally namespace-qualified ('NS/name').

    .PARAMETER Type
        Disambiguate when a name exists across multiple recipe types.

    .EXAMPLE
        $r = Import-WorkLabRecipe -Name twoforest -Type lab
        $r.Data.Slug

    .EXAMPLE
        $app = Import-WorkLabRecipe -Name DomainController -Type app
        & $app.Install -ComputerName C -Config @{} -LabId twoforest

    .OUTPUTS
        pscustomobject (Reference; plus Data for psd1, or Module+Install for app).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('lab', 'topology', 'component', 'app')]
        [string]$Type
    )

    $candidates = @(Get-WorkLabRecipe -Name $Name -Type $Type)
    if ($candidates.Count -eq 0) {
        throw "No recipe named '$Name'$(if ($Type) { " of type '$Type'" }) found. Run Get-WorkLabRecipe to list available recipes, or set `$env:WORKLAB_RECIPE_PATH."
    }

    $ref = $candidates[0]
    if ($candidates.Count -gt 1) {
        Write-PSFMessage -Level Verbose -Message "Recipe '{0}' matched {1} sources; using highest precedence: {2}" -StringValues $Name, $candidates.Count, $ref.ToString()
    }

    if ($ref.Type -eq 'app') {
        $mod = Import-Module -Name $ref.Path -PassThru -Force -ErrorAction Stop
        $install = $mod.ExportedCommands['Install-WorkLabAppRecipe']
        if (-not $install) {
            throw "App recipe '$($ref.Name)' ($($ref.Path)) does not export Install-WorkLabAppRecipe. App recipes must export that function. See docs/RECIPES.md."
        }
        $required = @('ComputerName', 'Config', 'LabId')
        $missing = $required | Where-Object { -not $install.Parameters.ContainsKey($_) }
        if ($missing) {
            throw "App recipe '$($ref.Name)' Install-WorkLabAppRecipe is missing required parameter(s): $($missing -join ', '). See docs/RECIPES.md for the required signature."
        }
        return [pscustomobject]@{
            Reference = $ref
            IsApp     = $true
            Module    = $mod
            Install   = $install
            Data      = $null
        }
    }

    $data = Import-PowerShellDataFile -LiteralPath $ref.Path -ErrorAction Stop
    [pscustomobject]@{
        Reference = $ref
        IsApp     = $false
        Module    = $null
        Install   = $null
        Data      = $data
    }
}
