@{
    PSDependOptions = @{
        AddToPath  = $true
        Target     = 'output/RequiredModules'
        Parameters = @{
            Repository = 'PSGallery'
        }
    }

    # --- Build / test toolchain ---
    InvokeBuild        = 'latest'
    Pester             = '5.5.0'
    PSScriptAnalyzer   = '1.25.0'   # pin: PSDepend 'latest' resolved to an older build that NREs on the Windows runner
    Sampler            = 'latest'   # conventions + future ModuleBuilder use

    # --- Runtime dependencies of the WorkLab modules ---
    PSFramework        = 'latest'   # structured logging across all cmdlets
    'Microsoft.PowerShell.SecretManagement' = 'latest'  # secret routing (vault-agnostic)

    # Provider runtime deps (resolved for build/test even though Phase 0
    # only wires Proxmox network ops).
    PSProxmoxVE        = '0.2.0'   # pin: needs guest-exec argv fix (#69) for the Phase 2.5 guest channel; also #58/#59/#64
}
