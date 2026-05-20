function Get-LabComputer {
    <#
    .SYNOPSIS
        Get the computers in a provisioned lab. (REAL)

    .DESCRIPTION
        Returns the lab's VMs as normalized provider objects (list-mode by
        slug), optionally filtered to one VM name.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .PARAMETER Name
        Optional VM-name filter (lab-<slug>-<role>NN).

    .EXAMPLE
        Get-LabComputer -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        pscustomobject normalized VM(s).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter()]
        [string]$Name
    )
    process {
        $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
        $provider = $ctx.Provider
        $pctx = New-WorkLabProviderContext -Provider $provider -Slug $ctx.Slug

        $vms = Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Get' -Noun 'Vm' `
            -Arguments @{ Context = $pctx }

        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $vms = $vms | Where-Object { $_.Name -eq $Name }
        }
        $vms
    }
}
