function Build-WorkLabImage {
    <#
    .SYNOPSIS
        Build a DISM-patched bootable Windows ISO into the image cache. (REAL)

    .DESCRIPTION
        Windows-only (DISM + ADK oscdimg). Copies the source ISO, mounts the
        selected install.wim edition, injects optional drivers/updates, writes
        an autounattend.xml (local-admin password from -AdminCredential or the
        SecretManagement secret worklab/image/local-admin/<name>), rebuilds a
        bootable ISO under <cache>/images/<name>/, and records a manifest.

        Idempotent: a matching manifest (same source checksum, edition,
        locale) with an existing ISO is returned unchanged unless -Force.

        On non-Windows this fast-fails by design (see docs/DECISIONS.md). The
        boot-install/sysprep/template-capture that consumes this ISO is
        orchestrated later (lazy hybrid template cache).

    .PARAMETER Name
        Logical image name (cache folder + manifest key).

    .PARAMETER SourceIso
        Path to the base Windows ISO.

    .PARAMETER Edition
        install.wim edition: integer index or edition name (default '1').

    .PARAMETER Locale
        Install locale (default 'en-US').

    .PARAMETER AdminCredential
        Build-time local-admin credential; else resolved from SecretManagement.

    .PARAMETER DriverPath
        Optional folder of drivers to inject (recursive).

    .PARAMETER UpdatePath
        Optional folder of .msu/.cab updates to inject.

    .PARAMETER Force
        Rebuild even if a matching manifest already exists.

    .EXAMPLE
        Build-WorkLabImage -Name ws2025-core -SourceIso D:\iso\ws2025.iso -Edition 2

    .OUTPUTS
        pscustomobject: Name, IsoPath, Existed, Manifest.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$SourceIso,

        [Parameter()]
        [string]$Edition = '1',

        [Parameter()]
        [string]$Locale = 'en-US',

        [Parameter()]
        [pscredential]$AdminCredential,

        [Parameter()]
        [string]$DriverPath,

        [Parameter()]
        [string]$UpdatePath,

        [Parameter()]
        [switch]$Force
    )

    Assert-WorkLabDismAvailable

    if (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
        throw "Source ISO not found: $SourceIso"
    }

    $dir = Join-Path (Get-WorkLabImageRoot) $Name
    $isoOut = Join-Path $dir "$Name.iso"
    $sourceSha = Get-WorkLabFileChecksum -Path $SourceIso

    $existing = Read-WorkLabImageManifest -Name $Name
    if ($existing -and -not $Force -and
        $existing.sourceSha256 -eq $sourceSha -and
        "$($existing.edition)" -eq $Edition -and
        $existing.locale -eq $Locale -and
        $existing.drivers -eq $DriverPath -and
        $existing.updates -eq $UpdatePath -and
        (Test-Path -LiteralPath $isoOut -PathType Leaf)) {
        Write-PSFMessage -Level Significant -Message "Image '{0}' is current; reconciled (no rebuild)." -StringValues $Name
        return [pscustomobject]@{ Name = $Name; IsoPath = $isoOut; Existed = $true; Manifest = $existing }
    }

    if (-not $PSCmdlet.ShouldProcess("$Name from $SourceIso", 'Build-WorkLabImage')) { return }

    $cred = Resolve-WorkLabImageAdminCredential -Name $Name -AdminCredential $AdminCredential
    $workDir = Join-Path $dir '_work'
    $mountDir = Join-Path $dir '_mount'
    Remove-Item -LiteralPath $workDir, $mountDir -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Force -Path $dir

    try {
        Expand-WorkLabIsoSource -SourceIso $SourceIso -WorkDir $workDir | Out-Null
        $wim = Join-Path $workDir 'sources/install.wim'

        Mount-WorkLabWim -WimPath $wim -Edition $Edition -MountDir $mountDir | Out-Null
        try {
            Add-WorkLabWimContent -MountDir $mountDir -DriverPath $DriverPath -UpdatePath $UpdatePath
            Dismount-WorkLabWim -MountDir $mountDir
        }
        catch {
            Dismount-WorkLabWim -MountDir $mountDir -Discard
            throw
        }

        New-WorkLabAutounattend -Edition $Edition -AdminPassword $cred.Password -Locale $Locale `
            -OutFile (Join-Path $workDir 'autounattend.xml') | Out-Null

        New-WorkLabBootableIso -WorkDir $workDir -IsoPath $isoOut | Out-Null

        $manifest = [ordered]@{
            schema       = 'worklab.image/v1'
            name         = $Name
            sourceIso    = $SourceIso
            sourceSha256 = $sourceSha
            edition      = $Edition
            locale       = $Locale
            drivers      = $DriverPath
            updates      = $UpdatePath
            isoFile      = $isoOut
            isoSha256    = (Get-WorkLabFileChecksum -Path $isoOut)
            builtUtc     = [datetime]::UtcNow.ToString('o')
        }
        Write-WorkLabImageManifest -Name $Name -Manifest $manifest | Out-Null
        Write-PSFMessage -Level Significant -Message "Built image '{0}' -> {1}" -StringValues $Name, $isoOut

        return [pscustomobject]@{
            Name = $Name; IsoPath = $isoOut; Existed = $false
            Manifest = ([pscustomobject]$manifest)
        }
    }
    finally {
        Remove-Item -LiteralPath $workDir, $mountDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
