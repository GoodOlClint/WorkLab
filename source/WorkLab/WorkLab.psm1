#Requires -Version 7.0

# Module root, used by the recipe discovery seam (in-tree resolution).
$script:WorkLabModuleRoot = $PSScriptRoot

# The ONLY module-scoped mutable state in the framework: the provider
# registration table. Lab state never lives here — it flows via LabContext.
$script:WorkLabProviders = @{}

# --- Classes (order matters: dependents last) ---
$classOrder = @(
    'RecipeReference'
    'ProviderRegistration'
    'LabContext'
)
foreach ($c in $classOrder) {
    . (Join-Path $PSScriptRoot "Classes/$c.ps1")
}

# --- Private helpers ---
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# --- Public cmdlets ---
$public = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($f in $public) { . $f.FullName }

Export-ModuleMember -Function $public.BaseName

# --- Structured logging (PSFramework) ---
Initialize-WorkLabLogging
