function Resolve-WorkLabImageAdminCredential {
    <#
    .SYNOPSIS
        Resolve the build-time local-admin credential for an image.
    .DESCRIPTION
        Uses the explicit credential if given, else reads it from
        SecretManagement at worklab/image/local-admin/<name> (the WorkLab
        secret namespace). Fails fast with a teaching message if neither is
        available.
    #>
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][pscredential]$AdminCredential
    )

    if ($AdminCredential) { return $AdminCredential }

    try {
        $secret = Get-WorkLabSecret -Slug 'image' -Role 'local-admin' -Name $Name -ErrorAction Stop
    }
    catch {
        throw "No build admin credential for image '$Name'. Pass -AdminCredential, or store one: New-WorkLabSecret -Slug image -Role local-admin -Name $Name -Secret (Get-Credential). ($($_.Exception.Message))"
    }
    if ($secret -is [pscredential]) { return $secret }
    throw "Secret worklab/image/local-admin/$Name is not a PSCredential. Store it as a credential: New-WorkLabSecret -Slug image -Role local-admin -Name $Name -Secret (Get-Credential)."
}
