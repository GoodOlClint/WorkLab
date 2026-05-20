function Test-WorkLabProviderConnection {
    <#
    .SYNOPSIS
        Proxmox provider: connectivity health check + capability flags. (REAL)

    .DESCRIPTION
        Connects with PSProxmoxVE and verifies the session. Returns a
        capability object the core uses to decide what the provider supports.

    .PARAMETER Context
        LabContext or property bag carrying provider Options.

    .EXAMPLE
        Test-WorkLabProviderConnection -Context @{ Options = @{ Server='pve.lan'; ApiToken=$t; Zone='labz' } }

    .OUTPUTS
        pscustomobject capability/health report.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    $healthy = $false
    $detail = $null
    try {
        $null = Connect-WorkLabProxmox -Settings $settings
        $healthy = [bool](Test-PveConnection -ErrorAction Stop)
        $detail = 'connected'
    }
    catch {
        $detail = $_.Exception.Message
    }

    [pscustomobject]@{
        Provider     = 'Proxmox'
        Healthy      = $healthy
        Server       = $settings.Server
        Zone         = $settings.Zone
        Detail       = $detail
        Capabilities = [pscustomobject]@{
            Network    = $true   # Phase 0 REAL
            Iso        = $true   # Phase 1 REAL
            Template   = $true   # Phase 1 REAL
            Vm         = $true   # Phase 1 REAL
            Checkpoint = $true   # Phase 1 REAL
        }
    }
}
