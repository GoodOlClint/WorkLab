function Remove-WorkLabSecret {
    <#
    .SYNOPSIS
        Delete a secret from the WorkLab namespace.

    .DESCRIPTION
        Removes worklab/<slug>/<role>/<name>. The owning vault is discovered
        via Get-SecretInfo (Remove-Secret requires an explicit vault). WorkLab
        never selects a vault for the user.

    .PARAMETER Slug
        Lab slug (3-12 lowercase alphanumeric).

    .PARAMETER Role
        Namespace segment: e.g. local-admin, domain-admin, svc.

    .PARAMETER Name
        Secret leaf name.

    .EXAMPLE
        Remove-WorkLabSecret -Slug twoforest -Role svc -Name sql01

    .OUTPUTS
        None.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Name
    )

    Assert-WorkLabSecretVault
    $secretName = New-WorkLabSecretPath -Slug $Slug -Role $Role -Name $Name

    $info = Get-SecretInfo -Name $secretName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $info) {
        Write-PSFMessage -Level Warning -Message "Secret '{0}' not found; nothing to remove." -StringValues $secretName
        return
    }

    if ($PSCmdlet.ShouldProcess($secretName, "Remove-Secret (vault: $($info.VaultName))")) {
        Remove-Secret -Name $secretName -Vault $info.VaultName -ErrorAction Stop
        Write-PSFMessage -Level Significant -Message "Removed secret '{0}' from vault '{1}'" -StringValues $secretName, $info.VaultName
    }
}
