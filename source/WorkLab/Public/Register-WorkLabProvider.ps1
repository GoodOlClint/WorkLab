function Register-WorkLabProvider {
    <#
    .SYNOPSIS
        Register a hypervisor provider under a logical name.

    .DESCRIPTION
        Binds a logical provider name (e.g. 'Proxmox') to an implementing
        module (e.g. 'WorkLab.Proxmox') plus non-secret connection options.
        The registration table is the only module-scoped mutable state in the
        framework. Re-registering the same name replaces the prior binding.

    .PARAMETER Name
        Logical provider name used by recipes and lab contexts.

    .PARAMETER ModuleName
        Implementing provider module. Defaults to 'WorkLab.<Name>'.

    .PARAMETER Options
        Non-secret connection settings (host, node, port, ...). Secrets must
        be stored via New-WorkLabSecret, never here.

    .PARAMETER PassThru
        Emit the resulting ProviderRegistration.

    .EXAMPLE
        Register-WorkLabProvider -Name Proxmox -Options @{ Server='pve.lan'; Node='pve1' }

    .OUTPUTS
        ProviderRegistration (with -PassThru)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$ModuleName,

        [Parameter()]
        [hashtable]$Options = @{},

        [Parameter()]
        [switch]$PassThru
    )

    if ([string]::IsNullOrWhiteSpace($ModuleName)) {
        $ModuleName = "WorkLab.$Name"
    }

    # Available if already loaded (e.g. imported by path, as the quickstart
    # does) OR discoverable on PSModulePath.
    $isAvailable = (Get-Module -Name $ModuleName) -or (Get-Module -ListAvailable -Name $ModuleName)
    if (-not $isAvailable) {
        throw "Provider module '$ModuleName' is not available. Import it (Import-Module <path>/$ModuleName) or build the monorepo (./build.ps1), then retry Register-WorkLabProvider -Name $Name."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Register provider -> $ModuleName")) {
        $reg = [ProviderRegistration]::new($Name, $ModuleName, $Options)
        $script:WorkLabProviders[$Name] = $reg
        Write-PSFMessage -Level Significant -Message "Registered provider '{0}' -> {1}" -StringValues $Name, $ModuleName
        if ($PassThru) { $reg }
    }
}
