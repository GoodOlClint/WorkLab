@{
    # Top-level lab definition. The ONLY place provider mapping lives.
    Schema   = 'worklab.lab/v1'
    Slug     = 'helloworld'          # 3-12 lowercase alphanumeric, no hyphens
    Topology = 'single-domain'       # -> topologies/single-domain.topology.psd1

    # Provider binding (hypervisor knowledge is confined to this block).
    Provider = @{
        Name    = 'Proxmox'
        Options = @{
            Server = 'pve.lab.local'
            Zone   = 'labzone'        # pre-created SDN VLAN zone
            # Auth (ApiToken/Credential) is supplied at Register-WorkLabProvider
            # time or via SecretManagement — never stored in a recipe.
        }
    }

    # Apps installed onto computed hosts after base config.
    Apps = @(
        @{ Recipe = 'DomainController'; Target = 'dc01'; Config = @{ DomainName = 'contoso.local' } }
    )
}
