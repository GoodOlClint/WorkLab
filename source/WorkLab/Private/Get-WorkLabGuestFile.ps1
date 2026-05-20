function Get-WorkLabGuestFile {
    <#
    .SYNOPSIS
        Read a file from a guest VM via the provider guest channel.
    .DESCRIPTION
        Thin dispatch wrapper over Read-WorkLabProviderGuestFile.
        Hypervisor-agnostic.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Path
    )
    Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Read' -Noun 'GuestFile' -Arguments @{
        Context = $Context; VmName = $VmName; Path = $Path
    }
}
