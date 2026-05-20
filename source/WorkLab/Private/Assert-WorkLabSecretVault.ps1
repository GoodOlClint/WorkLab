function Assert-WorkLabSecretVault {
    <#
    .SYNOPSIS
        Fail fast unless SecretManagement is usable.
    .DESCRIPTION
        WorkLab is vault-agnostic: it never selects or registers a vault. It
        requires Microsoft.PowerShell.SecretManagement to be present and a
        usable default vault (or exactly one registered vault). See
        docs/DECISIONS.md.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$RequireDefaultForWrite
    )

    if (-not (Get-Command -Name Get-SecretVault -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.PowerShell.SecretManagement is not available. Install it (Install-Module Microsoft.PowerShell.SecretManagement) and register a vault with Register-SecretVault.'
    }

    $vaults = @(Get-SecretVault -ErrorAction Stop)
    if ($vaults.Count -eq 0) {
        throw 'No SecretManagement vault is registered. WorkLab does not pick a vault for you. Register one, e.g.: Register-SecretVault -Name Local -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault.'
    }

    $hasDefault = [bool]@($vaults | Where-Object { $_.IsDefault })
    if ($RequireDefaultForWrite -and -not $hasDefault -and $vaults.Count -gt 1) {
        throw "Multiple SecretManagement vaults are registered but none is the default; writes are ambiguous. Mark one default: Set-SecretVaultDefault -Name <vault>."
    }
}
