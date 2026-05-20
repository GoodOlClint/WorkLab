function Wait-WorkLabProviderVmStopped {
    <#
    .SYNOPSIS
        Block until a provider VM reports stopped (the build-complete signal).
    .DESCRIPTION
        The image autounattend ends with sysprep /shutdown, so the install
        VM powering off marks build completion. Polls the provider's
        Get-WorkLabProviderVm via the dispatch seam. Throws on timeout or if
        the VM disappears.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][int]$TimeoutSeconds = 1800,
        [Parameter()][int]$PollSeconds = 15
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $vm = Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Get' -Noun 'Vm' `
            -Arguments @{ Context = $Context; VmName = $VmName }

        if (-not $vm) {
            throw "Build VM '$VmName' disappeared before it stopped; cannot capture a template."
        }
        if ($vm.Status -eq 'stopped') {
            Write-PSFMessage -Level Significant -Message "Build VM '{0}' stopped; ready to templatize." -StringValues $VmName
            return
        }
        if ([datetime]::UtcNow -gt $deadline) {
            throw "Timed out after ${TimeoutSeconds}s waiting for build VM '$VmName' to sysprep/shutdown."
        }
        Start-Sleep -Seconds $PollSeconds
    }
}
