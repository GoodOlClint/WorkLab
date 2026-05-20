function Initialize-WorkLabLogging {
    <#
    .SYNOPSIS
        Configure PSFramework structured logging for WorkLab.
    .DESCRIPTION
        Registers a logfile logging provider writing structured entries under
        <state root>/logs. Idempotent: re-running just reconfigures the same
        provider instance. No module-scoped flag is used (no mutable module
        state per design).

        Logging is infrastructure, not a hard dependency: this function is
        best-effort and MUST NOT abort module import. PSFramework emits a
        benign non-terminating "TypeConverter ... already occurs" notice
        whenever a second copy is visible on the path (common once
        ./build.ps1 prepends output/RequiredModules in a session that already
        loaded PSFramework). That notice is not fatal and is swallowed here.
    #>
    [CmdletBinding()]
    param()

    # Only import if not already loaded — re-importing is what surfaces the
    # duplicate-TypeData notice; if it's already loaded, Write-PSFMessage works.
    if (-not (Get-Module -Name PSFramework)) {
        if (-not (Get-Module -ListAvailable -Name PSFramework)) {
            Write-Warning 'PSFramework not available; structured logging disabled. Run ./build.ps1 to resolve dependencies.'
            return
        }
        try {
            Import-Module PSFramework -ErrorAction Stop
        }
        catch {
            Write-Warning "PSFramework import reported: $($_.Exception.Message). Continuing with logging best-effort."
        }
    }

    if (-not (Get-Command -Name Set-PSFLoggingProvider -ErrorAction SilentlyContinue)) {
        Write-Warning 'PSFramework logging provider unavailable; structured logging disabled.'
        return
    }

    try {
        $logDir = Join-Path (Get-WorkLabStateRoot) 'logs'
        $null = New-Item -ItemType Directory -Force -Path $logDir
        Set-PSFLoggingProvider -Name 'logfile' -InstanceName 'WorkLab' `
            -FilePath (Join-Path $logDir 'worklab-%Date%.log') -Enabled $true -Wait $false
    }
    catch {
        Write-Warning "WorkLab structured logging setup skipped: $($_.Exception.Message)"
    }
}
