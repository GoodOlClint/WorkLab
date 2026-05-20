#Requires -Version 7.0

function Install-WorkLabAppRecipe {
    <#
    .SYNOPSIS
        App recipe: promote a host to a domain controller.
    .DESCRIPTION
        Reference app recipe. The required export contract is enforced by
        Import-WorkLabRecipe (see docs/RECIPES.md). Real DSC orchestration
        lands in Phase 5+; Phase 0 only demonstrates the contract.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$LabId,
        [Parameter()][pscredential]$Credential
    )

    Write-Warning "DomainController app recipe is a Phase 0 contract stub: no changes made to '$ComputerName' (lab '$LabId', domain '$($Config.DomainName)')."
    [pscustomobject]@{
        Recipe       = 'DomainController'
        ComputerName = $ComputerName
        LabId        = $LabId
        Applied      = $false
    }
}

Export-ModuleMember -Function Install-WorkLabAppRecipe
