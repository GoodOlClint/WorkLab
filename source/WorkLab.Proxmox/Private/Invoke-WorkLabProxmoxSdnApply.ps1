function Invoke-WorkLabProxmoxSdnApply {
    <#
    .SYNOPSIS
        Apply the Proxmox SDN configuration, tolerating transient ifreload flakes.

    .DESCRIPTION
        Wraps Invoke-PveSdnApply. Applying SDN triggers root@pam's
        "SRV networking - Reload" task, which runs `ifreload -a` on every node.
        ifupdown2 intermittently returns exit code 89 during that reload (a
        benign reload race when bridges/VLANs are brought up together) — the
        next apply almost always succeeds. Retry a few times on that transient
        before surfacing the failure, so a flaky reload doesn't fail an
        otherwise-correct network create/remove.

        A genuine, persistent SDN/config error still throws after the retries.

    .PARAMETER Session
        Active PveSession.

    .PARAMETER MaxAttempts
        Total attempts before giving up (default 3).

    .PARAMETER DelaySeconds
        Delay between attempts (default 5).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter()][int]$MaxAttempts = 3,
        [Parameter()][int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-PveSdnApply -Session $Session -Confirm:$false -ErrorAction Stop
            return
        }
        catch {
            $msg = $_.Exception.Message
            # Only retry the known-transient ifreload flake; anything else is real.
            $isTransientReload = $msg -match "ifreload -a' failed" -or $msg -match 'exit code 89'
            if (-not $isTransientReload -or $attempt -eq $MaxAttempts) {
                throw
            }
            Write-PSFMessage -Level Warning -Message "SDN apply hit a transient ifreload failure (attempt {0}/{1}): {2} — retrying in {3}s." `
                -StringValues $attempt, $MaxAttempts, $msg, $DelaySeconds
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}
