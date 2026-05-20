function Resolve-WorkLabComputerPlan {
    <#
    .SYNOPSIS
        Expand a lab recipe into its concrete computer plan.
    .DESCRIPTION
        Composes the discovery seam: lab -> topology -> components, deriving
        each computer's identity via LabContext (names are never authored).
        Phase 2 supports the single-domain topology (a DomainControllers
        group). Returns Context (LabContext), Lab data, and the Computers
        list (Role/Index/VmName/ComputerName/Component/Image).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LabRecipe,
        [Parameter(Mandatory)][string]$ProviderName
    )

    $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
    $lab = Import-WorkLabRecipe -Name $LabRecipe -Type lab

    if (-not $lab.Data.Topology) {
        throw "Lab recipe '$LabRecipe' has no 'Topology'. Add Topology = '<name>' to the .lab.psd1."
    }
    $topology = Import-WorkLabRecipe -Name $lab.Data.Topology -Type topology

    $groups = $topology.Data.DomainControllers
    if (-not $groups) {
        throw "Topology '$($lab.Data.Topology)' has no 'DomainControllers' group. Phase 2 supports the single-domain topology shape."
    }

    $computers = foreach ($g in $groups) {
        $comp = Import-WorkLabRecipe -Name $g.Component -Type component
        $role = $comp.Data.Role
        $image = $comp.Data.Image
        if ([string]::IsNullOrWhiteSpace($role)) {
            throw "Component '$($g.Component)' has no 'Role'."
        }
        if ([string]::IsNullOrWhiteSpace($image)) {
            throw "Component '$($g.Component)' has no 'Image'. Add Image = '<name>' (built via Build-WorkLabImage)."
        }
        $count = [int]($g.Count ?? 1)
        for ($n = 1; $n -le $count; $n++) {
            [pscustomobject]@{
                Role         = $role
                Index        = $n
                VmName       = $ctx.VmName($role, $n)
                ComputerName = $ctx.ComputerName($role, $n)
                Component    = $g.Component
                Image        = $image
            }
        }
    }

    [pscustomobject]@{
        Context   = $ctx
        Lab       = $lab
        Computers = [pscustomobject[]]$computers
    }
}
