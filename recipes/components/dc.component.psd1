@{
    # Single-host definition. No hypervisor-specific config here — provider
    # mapping happens only in the lab.psd1 (see docs/DECISIONS.md).
    Schema  = 'worklab.component/v1'
    Role    = 'dc'                 # used to compute names: lab-<slug>-dc01
    Image   = 'ws2025-core'        # cached image name (built via Build-WorkLabImage)
    OsSku   = 'WindowsServer2025-Datacenter-Core'
    Cpu     = 2
    MemoryGB = 4
    DiskGB  = 60
    BaseConfig = @{
        # DSC resources applied via Invoke-DscResource (method-call mode).
        TimeZone = 'UTC'
        Features = @('RSAT-AD-PowerShell')
    }
}
