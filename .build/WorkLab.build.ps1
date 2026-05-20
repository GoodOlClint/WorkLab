<#
    Invoke-Build task definitions for the WorkLab monorepo.
    Invoked by ../build.ps1. Iterates every module declared in build.yaml.
#>

$script:RepoRoot = Split-Path $PSScriptRoot -Parent
$script:SourceRoot = Join-Path $script:RepoRoot 'source'
$script:OutputRoot = Join-Path $script:RepoRoot 'output'

function Get-WorkLabBuildConfig {
    $yaml = Join-Path $script:RepoRoot 'build.yaml'
    # Minimal YAML read: we only need ModuleVersion + Modules list. Avoid a
    # YAML module dependency for Phase 0 by parsing the two fields we use.
    $lines = Get-Content -Path $yaml
    $version = ($lines | Where-Object { $_ -match '^\s*ModuleVersion:\s*' } |
        Select-Object -First 1) -replace "^\s*ModuleVersion:\s*'?([^']+)'?.*$", '$1'
    $modules = @()
    $inModules = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*Modules:\s*$') { $inModules = $true; continue }
        if ($inModules) {
            if ($l -match '^\s*-\s*(.+?)\s*$') { $modules += $Matches[1]; continue }
            if ($l -match '^\S') { break }
        }
    }
    [pscustomobject]@{ Version = $version.Trim(); Modules = $modules }
}

# Synopsis: Assemble each module from source/ into output/module/<name>/<version>.
task build {
    $cfg = Get-WorkLabBuildConfig
    $dest = Join-Path $script:OutputRoot 'module'
    foreach ($m in $cfg.Modules) {
        $src = Join-Path $script:SourceRoot $m
        if (-not (Test-Path $src)) {
            Write-Warning "Module source missing: $src (skipping)"
            continue
        }
        # Clean per-module target only (no global output/module wipe) so
        # back-to-back builds can't contend on the shared tree.
        $target = Join-Path $dest "$m/$($cfg.Version)"
        Remove-Item -Recurse -Force -Path $target -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Force -Path $target
        Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
        Write-Build Green "  built $m -> $target"
    }
}

# Synopsis: PSScriptAnalyzer over all module source.
task analyze {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $settings = Join-Path $script:RepoRoot '.build/ScriptAnalyzerSettings.psd1'
    $results = Invoke-ScriptAnalyzer -Path $script:SourceRoot -Recurse -Settings $settings
    if ($results) {
        $results | Format-Table -AutoSize | Out-String | Write-Build Yellow
        $errors = @($results | Where-Object Severity -EQ 'Error')
        if ($errors.Count -gt 0) {
            throw "PSScriptAnalyzer found $($errors.Count) error-severity finding(s)."
        }
    }
    Write-Build Green '  analyzer clean (no error-severity findings)'
}

# Synopsis: Run Pester 5 unit tests.
task unit {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $script:RepoRoot 'tests/Unit'
    $config.Run.Exit = $true
    $config.Run.Throw = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $script:OutputRoot 'testResults/unit.xml'
    Invoke-Pester -Configuration $config
}

# Synopsis: Run gated Pester integration tests (self-skip without env vars).
task integration {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $script:RepoRoot 'tests/Integration'
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $script:OutputRoot 'testResults/integration.xml'
    Invoke-Pester -Configuration $config
}

# Synopsis: analyze + unit.
task test analyze, unit

# Synopsis: Default — build then test.
task . build, test
