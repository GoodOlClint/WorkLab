function Get-WorkLabProxmoxContextValue {
    <#
    .SYNOPSIS
        Read a named value from any property bag (hashtable / object).
    .DESCRIPTION
        Providers stay decoupled from core classes: $Context may be a
        LabContext, a hashtable, or any object. This is the single accessor
        used to read Context and Options members without caring about type.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [hashtable]) { return $InputObject[$Name] }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}
