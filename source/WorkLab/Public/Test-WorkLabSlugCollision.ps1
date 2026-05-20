function Test-WorkLabSlugCollision {
    <#
    .SYNOPSIS
        Assert that a slug's computed VM names do not collide.

    .DESCRIPTION
        Validates the slug, computes the hypervisor VM names for the given
        roles (lab-<slug>-<role>01), and checks them against an existing-name
        set. The set is supplied explicitly via -ExistingVmName, or enumerated
        from a registered provider via -ProviderName (the provider path uses
        Get-WorkLabProviderVm and is fully wired here; the Proxmox VM query
        itself lands in Phase 1).

        Fails fast (throws) on collision unless -NoThrow is set. Always emits
        a result object.

    .PARAMETER Slug
        Lab slug (3-12 lowercase alphanumeric).

    .PARAMETER Role
        Role tokens to materialize (e.g. dc, mem, sql). One instance each.

    .PARAMETER ExistingVmName
        Names already present on the target (explicit form, used by tests and
        callers that pre-enumerated).

    .PARAMETER ProviderName
        Registered provider to enumerate existing VMs from (Phase 1 query).

    .PARAMETER NoThrow
        Return the result instead of throwing on collision.

    .EXAMPLE
        Test-WorkLabSlugCollision -Slug twoforest -Role dc,mem -ExistingVmName 'lab-other-dc01'

    .OUTPUTS
        pscustomobject: Slug, CandidateName, Collision, HasCollision.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Explicit')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Slug,

        [Parameter(Mandatory)]
        [string[]]$Role,

        [Parameter(ParameterSetName = 'Explicit')]
        [string[]]$ExistingVmName = @(),

        [Parameter(Mandatory, ParameterSetName = 'Provider')]
        [string]$ProviderName,

        [Parameter()]
        [switch]$NoThrow
    )

    [LabContext]::AssertValidSlug($Slug)

    $ctx = [LabContext]::new($Slug, $null, $null)
    $candidates = foreach ($r in $Role) { $ctx.VmName($r, 1) }

    if ($PSCmdlet.ParameterSetName -eq 'Provider') {
        $provider = Get-WorkLabProvider -Name $ProviderName
        $existing = Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Get' -Noun 'Vm' -Arguments @{
            Context = @{ Options = $provider.Options; ProviderName = $provider.Name; Slug = $Slug }
        }
        $ExistingVmName = @($existing | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.Name } })
    }

    $existingSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$ExistingVmName, [System.StringComparer]::OrdinalIgnoreCase)

    $collisions = @($candidates | Where-Object { $existingSet.Contains($_) })

    $result = [pscustomobject]@{
        Slug          = $Slug
        CandidateName = [string[]]$candidates
        Collision     = [string[]]$collisions
        HasCollision  = [bool]$collisions.Count
    }

    if ($result.HasCollision -and -not $NoThrow) {
        throw "Slug '$Slug' collides on the target with: $($collisions -join ', '). Choose a different Slug in the .lab.psd1 (3-12 lowercase alphanumeric)."
    }

    $result
}
