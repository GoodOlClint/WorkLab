function Wait-WorkLabProviderGuestAgentReady {
    <#
    .SYNOPSIS
        Block until a clone's guest is fully booted and ready (or timeout).
    .DESCRIPTION
        Runs a readiness *command* inside the guest through the provider's
        guest-exec seam and treats the guest as ready only when that command
        succeeds (exit 0) and its stdout matches the success pattern.

        This is deliberately stronger than a bare agent ping. qemu-ga answers a
        ping while Windows is still in OOBE, *before* the clone's final
        post-OOBE reboot -- a probe that returned on the first ping handed
        callers a guest that promptly rebooted and dropped the agent mid-
        operation (the guest exec would then fail with "agent is not running").
        The default probe asks Windows whether image deployment is complete
        (Setup\State\ImageState == IMAGE_STATE_COMPLETE), which only becomes true
        after OOBE finishes -- so it waits past every setup reboot, and a reboot
        in flight just fails the exec and keeps the loop polling.

        The probe is data (command + args + success pattern), defaulted for
        Windows, so a non-Windows guest can pass its own (e.g. a future Linux
        recipe supplying a systemd / cloud-init readiness command). Hypervisor-
        agnostic: dispatches through Invoke-WorkLabGuestCommand.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$PollSeconds = 5,
        [Parameter()][string]$ReadyCommand = 'reg.exe',
        [Parameter()][string[]]$ReadyArguments = @(
            'query', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State', '/v', 'ImageState'),
        [Parameter()][string]$ReadySuccessPattern = 'IMAGE_STATE_COMPLETE'
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $ready = $false
        try {
            $r = Invoke-WorkLabGuestCommand -Provider $Provider -Context $Context -VmName $VmName `
                -Command $ReadyCommand -Arguments $ReadyArguments
            if ($r.ExitCode -eq 0 -and "$($r.Stdout)" -match $ReadySuccessPattern) { $ready = $true }
        }
        catch {
            # Agent not up yet, or guest mid-reboot -- not ready, keep polling.
            Write-PSFMessage -Level Verbose -Message "Guest-ready probe on '{0}' not ready: {1}" -StringValues $VmName, $_.Exception.Message
        }
        if ($ready) {
            Write-PSFMessage -Level Significant -Message "Guest '{0}' ready (setup complete)." -StringValues $VmName
            return [pscustomobject]@{ VmName = $VmName; Reachable = $true; Ready = $true }
        }
        if ([datetime]::UtcNow -gt $deadline) {
            throw "Timed out after ${TimeoutSeconds}s waiting for guest '$VmName' to become ready (probe: $ReadyCommand $($ReadyArguments -join ' '))."
        }
        Start-Sleep -Seconds $PollSeconds
    }
}
