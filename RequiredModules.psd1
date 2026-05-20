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
    PSScriptAnalyzer   = 'latest'
    Sampler            = 'latest'   # conventions + future ModuleBuilder use

    # --- Runtime dependencies of the WorkLab modules ---
    PSFramework        = 'latest'   # structured logging across all cmdlets
    'Microsoft.PowerShell.SecretManagement' = 'latest'  # secret routing (vault-agnostic)

    # Provider runtime deps (resolved for build/test even though Phase 0
    # only wires Proxmox network ops).
    PSProxmoxVE        = 'latest'
}
