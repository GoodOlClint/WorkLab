function Get-WorkLabProvider {
    <#
    .SYNOPSIS
        Get registered WorkLab provider(s).

    .DESCRIPTION
        Returns the ProviderRegistration for a given logical name, or all
        registrations when -Name is omitted.

    .PARAMETER Name
        Logical provider name. Omit to list all.

    .EXAMPLE
        Get-WorkLabProvider
        Lists every registered provider.

    .EXAMPLE
        Get-WorkLabProvider -Name Proxmox

    .OUTPUTS
        ProviderRegistration
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    if ($PSBoundParameters.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace($Name)) {
        $reg = $script:WorkLabProviders[$Name]
        if (-not $reg) {
            throw "No provider registered as '$Name'. Register one with: Register-WorkLabProvider -Name $Name -Options @{ ... }"
        }
        return $reg
    }

    $script:WorkLabProviders.Values
}
