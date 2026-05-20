function Get-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: get VM(s). (REAL)

    .DESCRIPTION
        Single mode (-VmName): returns the one VM by derived identity, or
        nothing if absent. List mode (no -VmName, Context.Slug present):
        returns every VM whose name matches lab-<slug>-*. List mode backs
        Test-WorkLabSlugCollision.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node) and Slug (list mode).

    .PARAMETER VmName
        WorkLab VM name; omit for list mode.

    .EXAMPLE
        Get-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01

    .EXAMPLE
        Get-WorkLabProviderVm -Context @{ Options=$o; Slug='twoforest' }   # list mode

    .OUTPUTS
        pscustomobject normalized VM(s).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter()][string]$VmName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    if (-not [string]::IsNullOrWhiteSpace($VmName)) {
        $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
        if ($t.Resolved.Exists) {
            return (ConvertTo-WorkLabProxmoxVm -Vm $t.Resolved.Vm -Node $t.Settings.Node)
        }
        return
    }

    # List mode
    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    if ([string]::IsNullOrWhiteSpace($settings.Slug)) {
        throw 'Get-WorkLabProviderVm needs -VmName (single) or Context.Slug (list mode).'
    }
    $session = Connect-WorkLabProxmox -Settings $settings
    $prefix = "lab-$($settings.Slug)-"
    Get-PveVm -Session $session -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$prefix*" } |
        ForEach-Object { ConvertTo-WorkLabProxmoxVm -Vm $_ -Node $settings.Node }
}
