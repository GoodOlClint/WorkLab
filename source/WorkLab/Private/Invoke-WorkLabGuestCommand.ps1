function Invoke-WorkLabGuestCommand {
    <#
    .SYNOPSIS
        Run a command inside a guest VM via the provider guest channel.
    .DESCRIPTION
        Thin dispatch wrapper over Invoke-WorkLabProviderGuestCommand.
        Hypervisor-agnostic.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Command,
        [Parameter()][string[]]$Arguments,
        [Parameter()][int]$TimeoutSeconds = 60
    )

    $splat = @{ Context = $Context; VmName = $VmName; Command = $Command; TimeoutSeconds = $TimeoutSeconds }
    if ($Arguments) { $splat['Arguments'] = $Arguments }
    Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Invoke' -Noun 'GuestCommand' -Arguments $splat
}
