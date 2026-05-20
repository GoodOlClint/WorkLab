# ProviderRegistration — a hypervisor provider bound to a logical name.
# Options carries non-secret connection settings (host, node, port, ...).
# Secrets are never stored here; they are routed through SecretManagement.
class ProviderRegistration {
    [string]$Name          # logical name, e.g. 'Proxmox'
    [string]$ModuleName    # implementing module, e.g. 'WorkLab.Proxmox'
    [hashtable]$Options
    [datetime]$RegisteredAt

    ProviderRegistration([string]$name, [string]$moduleName, [hashtable]$options) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw 'ProviderRegistration requires a non-empty Name.'
        }
        if ([string]::IsNullOrWhiteSpace($moduleName)) {
            throw 'ProviderRegistration requires a non-empty ModuleName.'
        }
        $this.Name = $name
        $this.ModuleName = $moduleName
        $this.Options = if ($null -eq $options) { @{} } else { $options }
        $this.RegisteredAt = [datetime]::UtcNow
    }

    [string] ToString() {
        return ('{0} -> {1}' -f $this.Name, $this.ModuleName)
    }
}
