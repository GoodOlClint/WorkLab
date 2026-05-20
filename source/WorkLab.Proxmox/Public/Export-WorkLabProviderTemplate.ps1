function Export-WorkLabProviderTemplate {
    <#
    .SYNOPSIS
        Proxmox provider: convert a VM into a template. (REAL, idempotent)

    .DESCRIPTION
        Phase 1 primitive: stops the resolved VM if running and converts it to
        a Proxmox template. The sysprep/DISM capture pipeline that *produces*
        the VM to templatize is Phase 2 (Build-WorkLabImage orchestrates this
        primitive). Idempotent: an already-template VM is returned unchanged.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name to convert (lab-<slug>-<role>NN).

    .EXAMPLE
        Export-WorkLabProviderTemplate -Context $c -VmName lab-base-tpl01

    .OUTPUTS
        pscustomobject normalized template (IsTemplate=$true).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }
    $settings = $t.Settings; $session = $t.Session; $id = $t.Identity

    $alreadyTemplate = Get-PveVm -Node $settings.Node -VmId $id.VmId -TemplatesOnly `
        -Session $session -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($alreadyTemplate) {
        Write-Warning "VM '$VmName' is already a template; reconciled (no change)."
        return (ConvertTo-WorkLabProxmoxVm -Vm $alreadyTemplate -Node $settings.Node |
            Add-Member -NotePropertyName IsTemplate -NotePropertyValue $true -PassThru |
            Add-Member -NotePropertyName Existed -NotePropertyValue $true -PassThru)
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", 'New-PveTemplate')) {
        if ($t.Resolved.Vm.Status -eq 'running') {
            Stop-PveVm -Node $settings.Node -VmId $id.VmId -Wait -Session $session -Confirm:$false -ErrorAction Stop
        }
        New-PveTemplate -Node $settings.Node -VmId $id.VmId -Wait -Session $session -Confirm:$false -ErrorAction Stop
        $tpl = Get-PveVm -Node $settings.Node -VmId $id.VmId -Session $session -ErrorAction SilentlyContinue |
            Select-Object -First 1
        return (ConvertTo-WorkLabProxmoxVm -Vm $tpl -Node $settings.Node |
            Add-Member -NotePropertyName IsTemplate -NotePropertyValue $true -PassThru |
            Add-Member -NotePropertyName Existed -NotePropertyValue $false -PassThru)
    }
}
