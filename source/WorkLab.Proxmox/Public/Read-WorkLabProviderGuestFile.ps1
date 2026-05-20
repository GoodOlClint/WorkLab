function Read-WorkLabProviderGuestFile {
    <#
    .SYNOPSIS
        Proxmox provider: read a file from the guest via qemu-guest-agent. (REAL)

    .DESCRIPTION
        Wraps Read-PveVmGuestFile. Returns the file content as a UTF-8 string
        (PSProxmoxVE decodes the agent's base64 payload).

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER Path
        Source path in the guest OS.

    .EXAMPLE
        Read-WorkLabProviderGuestFile -Context $c -VmName lab-x-dc01 `
            -Path 'C:\Windows\Temp\dsc-result.json'

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, Path, Content.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }

    $content = Read-PveVmGuestFile -Node $t.Settings.Node -VmId $id.VmId -File $Path `
        -Session $t.Session -ErrorAction Stop

    [pscustomobject]@{
        Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId
        Path     = $Path; Content = $content
    }
}
