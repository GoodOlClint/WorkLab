function Invoke-WorkLabProviderGuestCommand {
    <#
    .SYNOPSIS
        Proxmox provider: run a command inside the guest via qemu-guest-agent. (REAL)

    .DESCRIPTION
        Wraps Invoke-PveVmGuestExec. Returns a normalized result with
        ExitCode/Stdout/Stderr so core helpers stay hypervisor-agnostic.
        PSProxmoxVE decodes Proxmox's base64 stdout/stderr to UTF-8.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER Command
        Path to the executable in the guest (e.g. 'pwsh' or
        'C:\Windows\System32\cmd.exe').

    .PARAMETER Arguments
        Arguments passed to the executable as a string array (no shell parsing).

    .PARAMETER TimeoutSeconds
        Per-call timeout for the agent exec (default 60s).

    .EXAMPLE
        Invoke-WorkLabProviderGuestCommand -Context $c -VmName lab-x-dc01 `
            -Command pwsh -Arguments '-NoProfile','-Command','$PSVersionTable.PSVersion'

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, ExitCode, Stdout, Stderr, Pid, Raw.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Command,
        [Parameter()][string[]]$Arguments,
        [Parameter()][int]$TimeoutSeconds = 60,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }

    $exec = @{
        Node    = $t.Settings.Node
        VmId    = $id.VmId
        Command = $Command
        Timeout = $TimeoutSeconds
        Session = $t.Session
        ErrorAction = 'Stop'
    }
    if ($Arguments) { $exec['Args'] = $Arguments }
    $raw = Invoke-PveVmGuestExec @exec

    [pscustomobject]@{
        Provider = 'Proxmox'
        VmName   = $VmName
        VmId     = $id.VmId
        ExitCode = $raw.ExitCode
        Stdout   = $raw.Stdout
        Stderr   = $raw.Stderr
        Pid      = $raw.Pid
        Raw      = $raw
    }
}
