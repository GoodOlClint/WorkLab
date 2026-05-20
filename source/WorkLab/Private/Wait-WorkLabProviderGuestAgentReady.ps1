function Wait-WorkLabProviderGuestAgentReady {
    <#
    .SYNOPSIS
        Block until a clone's guest agent reports reachable (or timeout).
    .DESCRIPTION
        Polls the provider's Test-WorkLabProviderGuestAgent via the dispatch
        seam. Hypervisor-agnostic. Returns when Reachable=$true. Throws on
        timeout.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$PollSeconds = 5
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $r = Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Test' -Noun 'GuestAgent' `
            -Arguments @{ Context = $Context; VmName = $VmName }
        if ($r.Reachable) {
            Write-PSFMessage -Level Significant -Message "Guest agent reachable on '{0}'." -StringValues $VmName
            return $r
        }
        if ([datetime]::UtcNow -gt $deadline) {
            throw "Timed out after ${TimeoutSeconds}s waiting for guest agent on '$VmName'."
        }
        Start-Sleep -Seconds $PollSeconds
    }
}
