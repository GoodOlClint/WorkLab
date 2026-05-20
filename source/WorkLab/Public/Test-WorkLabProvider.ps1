function Test-WorkLabProvider {
    <#
    .SYNOPSIS
        Health-check a registered provider via its module.

    .DESCRIPTION
        Dispatches to the provider module's Test-WorkLabProviderConnection,
        which performs a connectivity check and returns capability flags. Core
        never contains hypervisor-specific code; this only routes the call.

    .PARAMETER Name
        Logical provider name (must be registered).

    .EXAMPLE
        Test-WorkLabProvider -Name Proxmox

    .OUTPUTS
        The provider's capability/health object.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $provider = Get-WorkLabProvider -Name $Name
    Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Test' -Noun 'Connection' -Arguments @{
        Context = @{ Options = $provider.Options; ProviderName = $provider.Name }
    }
}
