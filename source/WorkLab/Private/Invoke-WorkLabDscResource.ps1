function Invoke-WorkLabDscResource {
    <#
    .SYNOPSIS
        Apply a DSC resource inside a guest VM via the provider guest channel.
    .DESCRIPTION
        Generates a small in-guest script that runs Invoke-DscResource Test ->
        (Set if needed) -> Test, pushes the script + reads back a JSON result.
        Uses Windows PowerShell 5.1 (`powershell.exe`, always present) so the
        guest does not need pwsh 7. Property hashtable is transported as
        base64-encoded JSON (avoids any embedded-quote escaping pitfalls) and
        reconstructed via flat ConvertFrom-Json + PSObject walk (PS 5.1 lacks
        ConvertFrom-Json -AsHashtable).

        Returns normalized {InDesiredStateBefore/After, SetApplied, Error,
        ExitCode, Stderr}. Phase 2.5 callers exercise built-in resources
        (File/Script) for which no extra modules need shipping; future
        role recipes deliver their own modules through this same channel.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$ResourceName,
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][hashtable]$Property,
        [Parameter()][int]$TimeoutSeconds = 600
    )

    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $scriptPath = "C:\Windows\Temp\wl-dsc-$id.ps1"
    $resultPath = "C:\Windows\Temp\wl-dsc-$id.json"
    $propsJson = ($Property | ConvertTo-Json -Depth 6 -Compress)
    $propsB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($propsJson))

    $script = @"
`$ErrorActionPreference = 'Stop'
`$result = [ordered]@{
    InDesiredStateBefore = `$null
    SetApplied = `$false
    InDesiredStateAfter = `$null
    Error = `$null
}
try {
    `$json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$propsB64'))
    `$propsObj = `$json | ConvertFrom-Json
    `$props = @{}
    `$propsObj.PSObject.Properties | ForEach-Object { `$props[`$_.Name] = `$_.Value }

    `$t1 = Invoke-DscResource -Name '$ResourceName' -ModuleName '$ModuleName' -Property `$props -Method Test
    `$result.InDesiredStateBefore = [bool]`$t1.InDesiredState
    if (-not `$t1.InDesiredState) {
        Invoke-DscResource -Name '$ResourceName' -ModuleName '$ModuleName' -Property `$props -Method Set | Out-Null
        `$result.SetApplied = `$true
        `$t2 = Invoke-DscResource -Name '$ResourceName' -ModuleName '$ModuleName' -Property `$props -Method Test
        `$result.InDesiredStateAfter = [bool]`$t2.InDesiredState
    } else {
        `$result.InDesiredStateAfter = `$true
    }
} catch {
    `$result.Error = `$_.Exception.Message
}
# Write UTF-8 *without* a BOM. The guest runs Windows PowerShell 5.1, whose
# Set-Content -Encoding utf8 prepends a BOM that then trips ConvertFrom-Json on
# read-back ("Unexpected character encountered ... 'ï'").
[System.IO.File]::WriteAllText('$resultPath', (`$result | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding(`$false)))
"@

    if (-not $PSCmdlet.ShouldProcess("$VmName : $ModuleName/$ResourceName", 'Invoke-DscResource via guest channel')) { return }

    Push-WorkLabGuestFile -Provider $Provider -Context $Context -VmName $VmName -Path $scriptPath -Content $script | Out-Null

    $exec = Invoke-WorkLabGuestCommand -Provider $Provider -Context $Context -VmName $VmName `
        -Command 'powershell.exe' `
        -Arguments '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath `
        -TimeoutSeconds $TimeoutSeconds

    $fetched = Get-WorkLabGuestFile -Provider $Provider -Context $Context -VmName $VmName -Path $resultPath
    # Defensively strip a leading UTF-8 BOM (U+FEFF) before parsing -- guest
    # files written by Windows PowerShell can carry one and ConvertFrom-Json
    # rejects it.
    $resultObj = "$($fetched.Content)".TrimStart([char]0xFEFF) | ConvertFrom-Json

    [pscustomobject]@{
        VmName               = $VmName
        ResourceName         = $ResourceName
        ModuleName           = $ModuleName
        InDesiredStateBefore = [bool]$resultObj.InDesiredStateBefore
        SetApplied           = [bool]$resultObj.SetApplied
        InDesiredStateAfter  = [bool]$resultObj.InDesiredStateAfter
        Error                = $resultObj.Error
        ExitCode             = $exec.ExitCode
        Stderr               = $exec.Stderr
    }
}
