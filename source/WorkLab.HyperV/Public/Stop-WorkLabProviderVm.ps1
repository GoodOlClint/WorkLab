function Stop-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Hyper-V provider: stop a VM. (Phase 0 stub.)

    .DESCRIPTION
        Part of the WorkLab provider contract (see docs/PROVIDERS.md). The
        core WorkLab module dispatches here via dynamic command resolution.
        Not implemented in Phase 0 for the Hyper-V provider (Phase 7).

    .PARAMETER Context
        LabContext instance or a hashtable property bag carrying provider
        Options and identity. Typed [object] so providers stay decoupled
        from the core WorkLab classes.

    .EXAMPLE
        Stop-WorkLabProviderVm -Context $ctx

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
        "Stop-WorkLabProviderVm is not implemented for the Hyper-V provider yet (Phase 7). " +
        "See docs/PROVIDERS.md for the contract and the phased build plan in README.md.")
}