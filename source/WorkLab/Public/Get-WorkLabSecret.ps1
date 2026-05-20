function Get-WorkLabSecret {
    <#
    .SYNOPSIS
        Retrieve a secret from the WorkLab namespace.

    .DESCRIPTION
        Reads worklab/<slug>/<role>/<name> from whatever vault
        SecretManagement routes to. WorkLab never selects a vault.

    .PARAMETER Slug
        Lab slug (3-12 lowercase alphanumeric).

    .PARAMETER Role
        Namespace segment: e.g. local-admin, domain-admin, svc.

    .PARAMETER Name
        Secret leaf name.

    .PARAMETER AsPlainText
        Return string secrets as plain text instead of SecureString.

    .EXAMPLE
        Get-WorkLabSecret -Slug twoforest -Role domain-admin -Name contoso.local

    .OUTPUTS
        The stored secret (SecureString/PSCredential/hashtable/string).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][switch]$AsPlainText
    )

    Assert-WorkLabSecretVault
    $secretName = New-WorkLabSecretPath -Slug $Slug -Role $Role -Name $Name
    Write-PSFMessage -Level Verbose -Message "Reading secret '{0}'" -StringValues $secretName
    Get-Secret -Name $secretName -AsPlainText:$AsPlainText -ErrorAction Stop
}
