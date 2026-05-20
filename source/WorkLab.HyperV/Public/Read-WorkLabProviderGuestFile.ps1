function Read-WorkLabProviderGuestFile {
    <#
    .SYNOPSIS
        Hyper-V provider: read a file from the guest via the guest agent. (Phase 0 stub.)

    .DESCRIPTION
        Part of the WorkLab provider contract guest channel
        (see docs/PROVIDERS.md). Not implemented in Phase 0 for the
        Hyper-V provider (Phase 7). Real signature accepts
        -VmName plus op-specific parameters; see the Proxmox implementation
        for the concrete shape.

    .PARAMETER Context
        LabContext instance or hashtable property bag carrying provider
        Options. Typed [object] so providers stay decoupled from core classes.

    .EXAMPLE
        Read-WorkLabProviderGuestFile -Context $ctx

    .OUTPUTS
        Throws [System.NotImplementedException] in Phase 0.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )
    throw [System.NotImplementedException]::new(
        "Read-WorkLabProviderGuestFile is not implemented for the Hyper-V provider yet (Phase 7). " +
        "See docs/PROVIDERS.md for the contract and the phased build plan in README.md.")
}