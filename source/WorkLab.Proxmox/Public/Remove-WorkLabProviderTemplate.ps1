function Remove-WorkLabProviderTemplate {
    <#
    .SYNOPSIS
        Proxmox provider: remove a template. (REAL, idempotent)

    .DESCRIPTION
        Removes the template resolved by name (purging its disks). Idempotent:
        a missing template is a no-op.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER Name
        Template name (a WorkLab VM name).

    .EXAMPLE
        Remove-WorkLabProviderTemplate -Context $c -Name lab-base-tpl01

    .OUTPUTS
        pscustomobject: Name, Removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Node')
    $session = Connect-WorkLabProxmox -Settings $settings

    $tpl = Resolve-WorkLabProxmoxTemplate -Settings $settings -Session $session -Name $Name
    if (-not $tpl) {
        Write-Verbose "Template '$Name' not present; nothing to remove."
        return [pscustomobject]@{ Name = $Name; Removed = $false }
    }

    if ($PSCmdlet.ShouldProcess("$Name (VMID $($tpl.VmId))", 'Remove-PveTemplate')) {
        Remove-PveTemplate -Node $settings.Node -VmId $tpl.VmId -Purge -Wait `
            -Session $session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $Name; Removed = $true }
    }
}
