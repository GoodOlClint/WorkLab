function Push-WorkLabGuestFile {
    <#
    .SYNOPSIS
        Write a file into a guest VM via the provider guest channel.
    .DESCRIPTION
        Thin dispatch wrapper over Write-WorkLabProviderGuestFile.
        Hypervisor-agnostic.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Write' -Noun 'GuestFile' -Arguments @{
        Context = $Context; VmName = $VmName; Path = $Path; Content = $Content
    }
}
