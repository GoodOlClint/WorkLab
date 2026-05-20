function Remove-WorkLabProviderIso {
    <#
    .SYNOPSIS
        Proxmox provider: remove a registered ISO. (REAL, idempotent)

    .DESCRIPTION
        Removes the named ISO from Options.IsoStorage. Idempotent: a missing
        ISO is a no-op.

    .PARAMETER Context
        Property bag carrying Options (Server/auth/Node/IsoStorage).

    .PARAMETER Name
        Stored ISO file name to remove.

    .EXAMPLE
        Remove-WorkLabProviderIso -Context $c -Name win2025.iso

    .OUTPUTS
        pscustomobject: Name, Removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Node', 'IsoStorage')
    $session = Connect-WorkLabProxmox -Settings $settings

    $item = Get-WorkLabProxmoxIso -Settings $settings -Session $session -FileName $Name | Select-Object -First 1
    if (-not $item) {
        Write-Verbose "ISO '$Name' not present in $($settings.IsoStorage); nothing to remove."
        return [pscustomobject]@{ Name = $Name; Removed = $false }
    }

    if ($PSCmdlet.ShouldProcess("$($item.VolId)", 'Remove-PveStorageContent')) {
        Remove-PveStorageContent -Node $settings.Node -Storage $settings.IsoStorage `
            -Volume $item.VolId -Session $session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $Name; Removed = $true }
    }
}
