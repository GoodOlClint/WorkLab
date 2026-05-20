function Wait-WorkLabProxmoxTask {
    <#
    .SYNOPSIS
        Block until a Proxmox task (UPID) completes.
    .DESCRIPTION
        Most PSProxmoxVE state-changing cmdlets accept -Wait and are used
        synchronously. This is the uniform fallback for any call that returns
        a bare UPID without having waited. A null/empty UPID is a no-op.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Session,
        [Parameter()][string]$Upid,
        [Parameter()][int]$TimeoutSeconds = 600
    )

    if ([string]::IsNullOrWhiteSpace($Upid)) { return }
    if ($Upid -notmatch '^UPID:') { return }

    Wait-PveTask -Node $Settings.Node -Upid $Upid -Session $Session `
        -Timeout ([System.TimeSpan]::FromSeconds($TimeoutSeconds)) -ErrorAction Stop
}
