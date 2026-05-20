function Invoke-WorkLabProviderCommand {
    <#
    .SYNOPSIS
        Dispatch a provider-contract call to the bound provider module.
    .DESCRIPTION
        Resolves <Verb>-WorkLabProvider<Noun> within the registered provider's
        module and invokes it. This is the single seam through which core ever
        touches a hypervisor — no hypervisor-specific code lives in core.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ProviderRegistration]$Provider,

        [Parameter(Mandatory)]
        [string]$Verb,

        [Parameter()]
        [string]$Noun = '',

        [Parameter()]
        [hashtable]$Arguments = @{}
    )

    $commandName = "$Verb-WorkLabProvider$Noun"
    # Resolve through the module object's ExportedCommands rather than
    # `Get-Command -Module`: every provider exports identically-named contract
    # cmdlets, so when more than one provider module is loaded the shared names
    # are shadowed in the global command table and `Get-Command -Module` finds
    # nothing for the shadowed module. ExportedCommands is per-module and
    # immune to load order.
    $module = Get-Module -Name $Provider.ModuleName
    $cmd = if ($module) { $module.ExportedCommands[$commandName] } else { $null }

    # Self-heal a missing/stale module handle (removed, partially loaded, or a
    # lingering empty handle in a long-lived session) with a forced re-import
    # before declaring the provider non-compliant.
    if (-not $cmd) {
        $module = Import-Module -Name $Provider.ModuleName -PassThru -Force -ErrorAction Stop
        $cmd = $module.ExportedCommands[$commandName]
    }
    if (-not $cmd) {
        throw "Provider '$($Provider.Name)' module '$($Provider.ModuleName)' does not export '$commandName'. The provider does not satisfy the WorkLab contract (see docs/PROVIDERS.md)."
    }
    Write-PSFMessage -Level Verbose -Message "Dispatching {0} to provider '{1}' ({2})" -StringValues $commandName, $Provider.Name, $Provider.ModuleName

    # The dispatch seam is internal: the caller (Initialize-Lab, Remove-Lab,
    # etc.) has already passed its own ShouldProcess gate, and the framework
    # is the only consumer of provider cmdlets. Force the inner call
    # non-interactive — provider Remove cmdlets are ConfirmImpact='High' by
    # default, and on a PSRP / non-interactive host the re-prompt's
    # PromptForChoice returns null and ShouldProcess throws NullReferenceException.
    $splat = [hashtable]::new($Arguments)
    $splat['Confirm'] = $false
    $splat['WhatIf']  = $false
    & $cmd @splat
}
