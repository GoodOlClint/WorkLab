function New-WorkLabSecret {
    <#
    .SYNOPSIS
        Store a secret under the WorkLab namespace.

    .DESCRIPTION
        Writes to whatever vault SecretManagement routes to (the user's
        registered default). WorkLab never selects a vault. The secret name
        is worklab/<slug>/<role>/<name>.

    .PARAMETER Slug
        Lab slug (3-12 lowercase alphanumeric).

    .PARAMETER Role
        Namespace segment: e.g. local-admin, domain-admin, svc.

    .PARAMETER Name
        Secret leaf name (computer, domain, or service account name).

    .PARAMETER Secret
        The secret value: string, securestring, pscredential, or hashtable.

    .PARAMETER PassThru
        Emit the resolved secret name.

    .EXAMPLE
        New-WorkLabSecret -Slug twoforest -Role local-admin -Name dc01 -Secret $cred

    .OUTPUTS
        string (the secret name, with -PassThru)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Secret,
        [Parameter()][switch]$PassThru
    )

    Assert-WorkLabSecretVault -RequireDefaultForWrite
    $secretName = New-WorkLabSecretPath -Slug $Slug -Role $Role -Name $Name

    if ($PSCmdlet.ShouldProcess($secretName, 'Set-Secret')) {
        Set-Secret -Name $secretName -Secret $Secret -ErrorAction Stop
        Write-PSFMessage -Level Significant -Message "Stored secret '{0}'" -StringValues $secretName
        if ($PassThru) { $secretName }
    }
}
