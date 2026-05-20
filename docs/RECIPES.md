# WorkLab Recipes

## Four recipe types

| Type | File convention | Purpose |
|---|---|---|
| Lab | `recipes/labs/<name>.lab.psd1` | Top-level definition. Declares `Slug`, provider mapping, composes a topology + apps. The **only** file that names a hypervisor. |
| Topology | `recipes/topologies/<name>.topology.psd1` | Reusable AD layout: forest/domain/DC counts, trusts, optional `Sites`. Hypervisor-agnostic. |
| Component | `recipes/components/<name>.component.psd1` | Single-host class: role, OS SKU, base DSC. Hypervisor-agnostic. |
| App | `recipes/apps/<App>/<App>.psd1` + `.psm1` | PowerShell module exporting `Install-WorkLabAppRecipe`. Orchestrates app install on a target host. |

Recipes are referenced **by name** in `lab.psd1`. On collisions across
sources, namespace-qualify: `Semperis.WorkLab.Recipes/dsp-install`.

### App recipe required export

```powershell
function Install-WorkLabAppRecipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$LabId,
        [Parameter()][pscredential]$Credential
    )
}
```

`Import-WorkLabRecipe` imports the app module and fails fast if the export is
missing or the required parameters are absent.

## Discovery seam

`Resolve-WorkLabRecipePath` returns recipe roots in **precedence order**;
`Get-WorkLabRecipe` enumerates them; `Import-WorkLabRecipe` loads the
highest-precedence match.

1. **In-tree** — `<module path>/../recipes/` when packaged/installed. In the
   monorepo dev layout, where `source/WorkLab/` and `recipes/` are repo-root
   siblings, resolution falls back to the nearest ancestor containing a
   `recipes/` directory.
2. **Side-loaded** — paths in `$env:WORKLAB_RECIPE_PATH`
   (`;`-separated on Windows, `:`-separated on Linux/macOS).
3. **Installed modules** — any module on `$env:PSModulePath` whose manifest
   `PrivateData.PSData.Tags` includes `'WorkLabRecipe'` and whose
   `PrivateData.WorkLab.RecipeRoot` names the recipe subdirectory.

Earlier sources win on name collision. A namespace-qualified name
(`Module/name`) targets a specific module source regardless of precedence.

Never hardcode a recipe path — always go through the seam (see
[DECISIONS.md](DECISIONS.md)).

### Module-shipped recipes

A module that ships recipes declares:

```powershell
PrivateData = @{
    PSData  = @{ Tags = @('WorkLabRecipe') }
    WorkLab = @{ RecipeRoot = 'recipes' }   # <ModuleBase>/recipes/{labs,...}
}
```

## Worked example

`recipes/labs/helloworld.lab.psd1` composes a topology, a component, and an
app:

```powershell
@{
    Schema   = 'worklab.lab/v1'
    Slug     = 'helloworld'
    Topology = 'single-domain'                 # topologies/single-domain.topology.psd1
    Provider = @{                              # ONLY place a hypervisor is named
        Name    = 'Proxmox'
        Options = @{ Server = 'pve.lab.local'; Zone = 'labzone' }
    }
    Apps = @(
        @{ Recipe = 'DomainController'; Target = 'dc01'; Config = @{ DomainName = 'contoso.local' } }
    )
}
```

`single-domain.topology.psd1` references the `dc` component
(`DomainControllers = @(@{ Component = 'dc'; Count = 1 })`), and
`dc.component.psd1` declares `Role = 'dc'`. The framework derives the
identities — `lab-helloworld-dc01` (hypervisor) and `HELLOWORLD-DC01`
(Windows) — so no recipe ever hardcodes a name.

Resolve and load it:

```powershell
Get-WorkLabRecipe -Type lab                       # discover
$lab = Import-WorkLabRecipe -Name helloworld -Type lab
$lab.Data.Slug                                    # 'helloworld'

$app = Import-WorkLabRecipe -Name DomainController -Type app
& $app.Install -ComputerName HELLOWORLD-DC01 -Config @{ DomainName = 'contoso.local' } -LabId helloworld
```
