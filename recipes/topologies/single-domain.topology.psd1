@{
    # Reusable AD layout. Forest/domain/DC counts + (optional) Sites.
    # Hypervisor-agnostic by design.
    Schema = 'worklab.topology/v1'
    Forest = @{
        RootDomain        = 'contoso.local'
        ForestMode        = 'WinThreshold'
        DomainMode        = 'WinThreshold'
    }
    DomainControllers = @(
        @{ Component = 'dc'; Count = 1 }
    )
    # Single subnet per lab by default. Add Sites for multi-subnet AD.
    Sites = @()
}
