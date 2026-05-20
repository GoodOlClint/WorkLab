function Test-WorkLabProviderGuestAgent {
    <#
    .SYNOPSIS
        Proxmox provider: probe whether the qemu-guest-agent is responding. (REAL)

    .DESCRIPTION
        Wraps Test-PveVmGuestAgent. Returns a normalized result so the core
        guest-channel helpers can stay hypervisor-agnostic.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .EXAMPLE
        Test-WorkLabProviderGuestAgent -Context $c -VmName lab-helloworld-dc01

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, Reachable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        return [pscustomobject]@{ Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId; Reachable = $false }
    }

    $reachable = $false
    try {
        $reachable = [bool](Test-PveVmGuestAgent -Node $t.Settings.Node -VmId $id.VmId -Session $t.Session -ErrorAction Stop)
    }
    catch {
        Write-PSFMessage -Level Verbose -Message "Test-PveVmGuestAgent failed for '{0}': {1}" -StringValues $VmName, $_.Exception.Message
    }

    [pscustomobject]@{ Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId; Reachable = $reachable }
}
