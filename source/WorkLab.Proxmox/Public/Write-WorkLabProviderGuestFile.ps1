function Write-WorkLabProviderGuestFile {
    <#
    .SYNOPSIS
        Proxmox provider: write a file into the guest via qemu-guest-agent. (REAL)

    .DESCRIPTION
        Wraps Write-PveVmGuestFile. Content is sent as a string; PSProxmoxVE
        base64-encodes for the underlying guest-agent file-write call. Use
        Get-WorkLabProxmoxNetworkIdentity / equivalent for binary payload
        chunking when a future caller needs it (Phase 2.5 callers send small
        text payloads — DSC scripts, JSON results).

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER Path
        Destination path in the guest OS (e.g. C:\Windows\Temp\worklab-dsc.ps1).

    .PARAMETER Content
        File content as a string.

    .EXAMPLE
        Write-WorkLabProviderGuestFile -Context $c -VmName lab-x-dc01 `
            -Path 'C:\Windows\Temp\hello.txt' -Content 'hi'

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, Path, Bytes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }

    if ($PSCmdlet.ShouldProcess("$VmName : $Path", "Write-PveVmGuestFile ($([math]::Round($Content.Length / 1KB, 2)) KB)")) {
        Write-PveVmGuestFile -Node $t.Settings.Node -VmId $id.VmId -File $Path `
            -Content $Content -Session $t.Session -Confirm:$false -ErrorAction Stop | Out-Null
        return [pscustomobject]@{
            Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId
            Path     = $Path; Bytes = $Content.Length
        }
    }
}
