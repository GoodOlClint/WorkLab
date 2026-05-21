function New-WorkLabProviderIso {
    <#
    .SYNOPSIS
        Proxmox provider: register an ISO into the lab ISO storage. (REAL, idempotent)

    .DESCRIPTION
        Registers an ISO by URL (downloaded server-side via
        Invoke-PveStorageDownload) or by uploading a local file
        (Send-PveFile) into Options.IsoStorage. Idempotent: if a file of the
        same name is already present it is returned unchanged.

    .PARAMETER Context
        Property bag carrying Options (Server/auth/Node/IsoStorage).

    .PARAMETER Url
        Source URL; the ISO is pulled server-side onto the node.

    .PARAMETER Path
        Local file path to upload.

    .PARAMETER Name
        Stored file name. Defaults to the leaf of Url/Path.

    .PARAMETER TimeoutSeconds
        Per-call HTTP timeout for the upload/download (PSProxmoxVE 0.1.3+).
        Default 1800 (30 min) — large Windows ISOs (~5 GB) routinely take
        longer than the legacy 100s HttpClient default. Bump higher if
        you're uploading multi-tens-of-GB images over a slow link.

    .EXAMPLE
        New-WorkLabProviderIso -Context $c -Url https://example/win.iso -Name win2025.iso

    .EXAMPLE
        New-WorkLabProviderIso -Context $c -Path /isos/patched.iso

    .OUTPUTS
        pscustomobject: Provider, Name, Storage, Existed, Raw.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByUrl')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory, ParameterSetName = 'ByUrl')]
        [string]$Url,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [int]$TimeoutSeconds = 1800,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Node', 'IsoStorage')

    $fileName = if ($Name) { $Name }
    elseif ($PSCmdlet.ParameterSetName -eq 'ByUrl') { Split-Path -Leaf ([uri]$Url).AbsolutePath }
    else { Split-Path -Leaf $Path }
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        throw 'Could not determine the ISO file name; pass -Name explicitly.'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByPath' -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ISO file not found: $Path"
    }

    $session = Connect-WorkLabProxmox -Settings $settings

    $existing = Get-WorkLabProxmoxIso -Settings $settings -Session $session -FileName $fileName | Select-Object -First 1
    if ($existing) {
        Write-Warning "ISO '$fileName' already present in $($settings.IsoStorage); reconciled (no change)."
        return [pscustomobject]@{
            Provider = 'Proxmox'; Name = $fileName; Storage = $settings.IsoStorage; Existed = $true; Raw = $existing
        }
    }

    $source = if ($PSCmdlet.ParameterSetName -eq 'ByUrl') { $Url } else { $Path }
    if ($PSCmdlet.ShouldProcess("$fileName -> $($settings.IsoStorage)", "register ISO from $source")) {
        if ($PSCmdlet.ParameterSetName -eq 'ByUrl') {
            Invoke-PveStorageDownload -Node $settings.Node -Storage $settings.IsoStorage `
                -Url $Url -Filename $fileName -ContentType 'iso' -Wait -Session $session `
                -TimeoutSeconds $TimeoutSeconds -Confirm:$false -ErrorAction Stop
        }
        else {
            Send-PveFile -Node $settings.Node -Storage $settings.IsoStorage -Path $Path `
                -ContentType 'iso' -Wait -Session $session `
                -TimeoutSeconds $TimeoutSeconds -Confirm:$false -ErrorAction Stop
        }
        $now = Get-WorkLabProxmoxIso -Settings $settings -Session $session -FileName $fileName | Select-Object -First 1
        return [pscustomobject]@{
            Provider = 'Proxmox'; Name = $fileName; Storage = $settings.IsoStorage; Existed = $false; Raw = $now
        }
    }
}
