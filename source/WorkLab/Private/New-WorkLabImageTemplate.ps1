function New-WorkLabImageTemplate {
    <#
    .SYNOPSIS
        Ensure a sysprepped provider template exists for a cached image.
    .DESCRIPTION
        Lazy hybrid template cache. If the template already exists it is
        returned (no rebuild). Otherwise: stand up an EPHEMERAL per-image SDN
        VNet, register the patched ISO, boot an install VM (autounattend
        installs + syspreps + powers off), convert it to a template, then
        tear the ephemeral VNet down.

        Note: the resulting template's NIC references the now-deleted build
        VNet; Initialize-Lab re-attaches each clone to its real per-lab VNet.

        All hypervisor interaction goes through the provider dispatch seam.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][string]$ImageName
    )

    $existing = Resolve-WorkLabImageTemplate -Provider $Provider -ImageName $ImageName
    if ($existing) {
        Write-PSFMessage -Level Significant -Message "Template for image '{0}' already exists; reusing (hybrid cache hit)." -StringValues $ImageName
        return [pscustomobject]@{ ImageName = $ImageName; TemplateName = $existing.TemplateName; Existed = $true; Raw = $existing }
    }

    $image = Get-WorkLabImage -Name $ImageName
    if (-not $image) {
        throw "Image '$ImageName' is not in the cache. Build it first: Build-WorkLabImage -Name $ImageName -SourceIso <iso>."
    }

    $slug = Get-WorkLabImageBuildSlug -Name $ImageName
    $tplName = "lab-$slug-tpl01"
    $ctx = @{ Options = $Provider.Options; Slug = $slug }
    $isoLeaf = Split-Path -Leaf $image.IsoPath

    if (-not $PSCmdlet.ShouldProcess($tplName, "build template for image '$ImageName'")) { return }

    try {
        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'New' -Noun 'Network' `
            -Arguments @{ Context = $ctx } | Out-Null
        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'New' -Noun 'Iso' `
            -Arguments @{ Context = $ctx; Path = $image.IsoPath } | Out-Null
        # Build the install VM as OVMF/UEFI + win11 (matches the proven Packer
        # template). The provider pairs ovmf with q35 + an efidisk0 and the
        # baked autounattend uses a matching UEFI/GPT disk layout.
        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'New' -Noun 'Vm' `
            -Arguments @{ Context = $ctx; VmName = $tplName; IsoName = $isoLeaf; Bios = 'ovmf'; OsType = 'win11'; Start = $true } | Out-Null

        # Generous stop timeout: the unattended install reads its media off the
        # SATA CD (ISO often on slower/networked storage) and the FirstLogon
        # virtio guest-tools + qemu-ga MSIs run before sysprep, so a from-scratch
        # build legitimately runs well past the 30-min default.
        Wait-WorkLabProviderVmStopped -Provider $Provider -Context $ctx -VmName $tplName -TimeoutSeconds 3600

        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Export' -Noun 'Template' `
            -Arguments @{ Context = $ctx; VmName = $tplName } | Out-Null
    }
    finally {
        # Always tear down the ephemeral build network AND the uploaded install
        # ISO, success or failure. Neither is needed once the template exists --
        # the clone's CD is emptied at clone time (Copy-WorkLabProviderVm) -- and
        # leaving the ISO behind leaks storage on every build.
        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Remove' -Noun 'Network' `
            -Arguments @{ Context = $ctx } -ErrorAction SilentlyContinue | Out-Null
        Invoke-WorkLabProviderCommand -Provider $Provider -Verb 'Remove' -Noun 'Iso' `
            -Arguments @{ Context = $ctx; Name = $isoLeaf } -ErrorAction SilentlyContinue | Out-Null
    }

    Write-PSFMessage -Level Significant -Message "Built template '{0}' for image '{1}'." -StringValues $tplName, $ImageName
    [pscustomobject]@{ ImageName = $ImageName; TemplateName = $tplName; Existed = $false; Raw = $null }
}
