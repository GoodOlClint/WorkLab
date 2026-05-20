#Requires -Version 7.0
<#
.SYNOPSIS
    WorkLab monorepo build bootstrap (Sampler-flavored, multi-module).

.DESCRIPTION
    Resolves build dependencies into a repo-local module path, then invokes
    Invoke-Build with the task files under .build/tasks/. Unlike stock Sampler
    (one module per repo) this build iterates every module under source/.

.PARAMETER Tasks
    Invoke-Build task(s) to run. Default: 'build','test'.

.PARAMETER ResolveDependency
    Force (re)resolution of build dependencies before running tasks.

.PARAMETER SkipDependencyCheck
    Skip the dependency presence check (assume already resolved).

.EXAMPLE
    ./build.ps1
    Resolves dependencies, builds all modules, runs unit tests + analyzer.

.EXAMPLE
    ./build.ps1 -Tasks test
    Runs analyzer + Pester unit tests only.

.EXAMPLE
    ./build.ps1 -Tasks integration
    Runs the gated integration tests (skipped unless env vars are set).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Tasks = @('build', 'test'),

    [Parameter()]
    [switch]$ResolveDependency,

    [Parameter()]
    [switch]$SkipDependencyCheck
)

$ErrorActionPreference = 'Stop'
# Note: deliberately NOT `Set-StrictMode -Version Latest` here. This bootstrap
# invokes Pester; StrictMode Latest leaks into the test runspace and trips
# Pester 5.5.0's mock machinery (generated scriptblocks) for reasons unrelated
# to WorkLab code. Strict-mode correctness is enforced by analyzer + tests.

# Normalize: `-File` passes `-Tasks build,test` as one literal token and
# `-Tasks build, test` as two; accept comma/space separated in any form.
$Tasks = @(($Tasks -join ' ') -split '[,\s]+' | Where-Object { $_ })
if (-not $Tasks) { $Tasks = @('build', 'test') }

$script:RepoRoot = $PSScriptRoot
$script:RequiredModulesPath = Join-Path $script:RepoRoot 'output/RequiredModules'

function Resolve-WorkLabBuildDependency {
    [CmdletBinding()]
    param()

    $manifestPath = Join-Path $script:RepoRoot 'RequiredModules.psd1'
    if (-not (Test-Path $manifestPath)) {
        throw "RequiredModules.psd1 not found at $manifestPath"
    }

    $required = Import-PowerShellDataFile -Path $manifestPath
    $null = New-Item -ItemType Directory -Force -Path $script:RequiredModulesPath

    foreach ($name in $required.Keys) {
        if ($name -eq 'PSDependOptions') { continue }

        $spec = $required[$name]
        $version = if ($spec -is [hashtable]) { $spec.Version } else { $spec }

        $alreadyThere = Get-ChildItem -Path $script:RequiredModulesPath -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -EQ $name

        if ($alreadyThere) {
            Write-Host "  [skip] $name already resolved" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  [save] $name $version" -ForegroundColor Cyan
        $saveParams = @{
            Name            = $name
            Path            = $script:RequiredModulesPath
            Repository      = 'PSGallery'
            Force           = $true
            ErrorAction     = 'Stop'
            AcceptLicense   = $true
        }
        if ($version -and $version -ne 'latest') {
            $saveParams['RequiredVersion'] = $version
        }
        Save-Module @saveParams
    }
}

function Test-WorkLabBuildDependency {
    [CmdletBinding()]
    param()
    # InvokeBuild is the minimum needed to run any task.
    $invokeBuild = Get-ChildItem -Path $script:RequiredModulesPath -Directory -ErrorAction SilentlyContinue |
        Where-Object Name -EQ 'InvokeBuild'
    return [bool]$invokeBuild
}

# --- Make the repo-local required modules discoverable ---
if ($env:PSModulePath -notlike "*$script:RequiredModulesPath*") {
    $sep = [System.IO.Path]::PathSeparator
    $env:PSModulePath = "$script:RequiredModulesPath$sep$env:PSModulePath"
}

# --- Resolve dependencies if asked or missing ---
if ($ResolveDependency -or (-not $SkipDependencyCheck -and -not (Test-WorkLabBuildDependency))) {
    Write-Host 'Resolving build dependencies...' -ForegroundColor Green
    Resolve-WorkLabBuildDependency
}

Import-Module InvokeBuild -ErrorAction Stop

# --- Run the build ---
$buildScript = Join-Path $script:RepoRoot '.build/WorkLab.build.ps1'
Write-Host "Invoke-Build tasks: $($Tasks -join ', ')" -ForegroundColor Green
Invoke-Build -Task $Tasks -File $buildScript -Result 'BuildResult'

if ($BuildResult.Error) {
    exit 1
}
exit 0
