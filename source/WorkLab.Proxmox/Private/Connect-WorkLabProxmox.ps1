function Connect-WorkLabProxmox {
    <#
    .SYNOPSIS
        Open a PveSession from normalized Proxmox settings.
    .DESCRIPTION
        Uses PSProxmoxVE Connect-PveServer. Returns the PveSession so callers
        pass it explicitly via -Session (no reliance on ambient module state).
        Auth precedence: ApiToken, then Credential.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][hashtable]$Settings
    )

    if (-not (Get-Command -Name Connect-PveServer -ErrorAction SilentlyContinue)) {
        throw 'PSProxmoxVE is not available. Install it (Install-Module PSProxmoxVE) or run ./build.ps1 to resolve dependencies.'
    }

    $connect = @{
        Server   = $Settings.Server
        PassThru = $true
    }
    if ($Settings.Port) { $connect['Port'] = [int]$Settings.Port }
    if ($Settings.SkipCertificateCheck) { $connect['SkipCertificateCheck'] = $true }

    if (-not [string]::IsNullOrWhiteSpace($Settings.ApiToken)) {
        $connect['ApiToken'] = $Settings.ApiToken
    }
    elseif ($Settings.Credential) {
        $connect['Credential'] = $Settings.Credential
    }
    else {
        throw "Proxmox provider needs Options.ApiToken ('user@realm!tokenid=uuid') or Options.Credential."
    }

    Connect-PveServer @connect
}
