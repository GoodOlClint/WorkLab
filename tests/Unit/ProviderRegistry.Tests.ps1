BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force

    # A discoverable fake provider so Register-WorkLabProvider's availability
    # check passes and dispatch can be exercised without a hypervisor.
    $script:FakeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "wl-prov-$([guid]::NewGuid().ToString('N'))"
    $modDir = Join-Path $script:FakeRoot 'WorkLab.Faker'
    New-Item -ItemType Directory -Force -Path $modDir | Out-Null
    Set-Content -Path (Join-Path $modDir 'WorkLab.Faker.psm1') -Value @'
function Test-WorkLabProviderConnection { param([object]$Context,[Parameter(ValueFromRemainingArguments)]$Rest) [pscustomobject]@{ Provider='Faker'; Healthy=$true; EchoedOptions=$Context.Options } }
function Get-WorkLabProviderVm { param([object]$Context,[Parameter(ValueFromRemainingArguments)]$Rest) @('lab-faker-dc01') }
Export-ModuleMember -Function Test-WorkLabProviderConnection,Get-WorkLabProviderVm
'@
    Set-Content -Path (Join-Path $modDir 'WorkLab.Faker.psd1') -Value @'
@{ RootModule='WorkLab.Faker.psm1'; ModuleVersion='0.1.0'; GUID='f0f0f0f0-0000-4000-8000-000000000001'; FunctionsToExport=@('Test-WorkLabProviderConnection','Get-WorkLabProviderVm') }
'@
    $sep = [System.IO.Path]::PathSeparator
    $env:PSModulePath = "$script:FakeRoot$sep$env:PSModulePath"
}

AfterAll {
    Remove-Item -Recurse -Force $script:FakeRoot -ErrorAction SilentlyContinue
}

Describe 'Register-WorkLabProvider / Get-WorkLabProvider' {
    It 'registers a discoverable provider and returns it' {
        $reg = Register-WorkLabProvider -Name Faker -Options @{ Server = 'fake.lan' } -PassThru
        $reg.Name | Should -Be 'Faker'
        $reg.ModuleName | Should -Be 'WorkLab.Faker'
        (Get-WorkLabProvider -Name Faker).Options.Server | Should -Be 'fake.lan'
    }
    It 'lists all providers when no name given' {
        (Get-WorkLabProvider).Name | Should -Contain 'Faker'
    }
    It 'fast-fails when the provider module is unavailable' {
        { Register-WorkLabProvider -Name Ghost } | Should -Throw -ExpectedMessage '*not available*'
    }
    It 'teaches how to register when asked for an unknown provider' {
        { Get-WorkLabProvider -Name Nope } | Should -Throw -ExpectedMessage '*Register-WorkLabProvider*'
    }
    It 'accepts a provider module imported by path (not on PSModulePath)' {
        # Regression: the quickstart imports providers by path; availability
        # must not require PSModulePath discovery.
        $pathRoot = Join-Path ([System.IO.Path]::GetTempPath()) "wl-pathprov-$([guid]::NewGuid().ToString('N'))"
        $md = Join-Path $pathRoot 'WorkLab.PathProv'
        New-Item -ItemType Directory -Force -Path $md | Out-Null
        Set-Content -Path (Join-Path $md 'WorkLab.PathProv.psm1') -Value 'function Test-WorkLabProviderConnection { param([object]$Context,[Parameter(ValueFromRemainingArguments)]$r) } Export-ModuleMember -Function Test-WorkLabProviderConnection'
        Set-Content -Path (Join-Path $md 'WorkLab.PathProv.psd1') -Value "@{ RootModule='WorkLab.PathProv.psm1'; ModuleVersion='0.1.0'; GUID='f0f0f0f0-0000-4000-8000-0000000000aa'; FunctionsToExport=@('Test-WorkLabProviderConnection') }"
        try {
            Import-Module (Join-Path $md 'WorkLab.PathProv.psd1') -Force   # by path; NOT on PSModulePath
            { Register-WorkLabProvider -Name PathProv -ModuleName WorkLab.PathProv } | Should -Not -Throw
            (Get-WorkLabProvider -Name PathProv).ModuleName | Should -Be 'WorkLab.PathProv'
        }
        finally {
            Remove-Module WorkLab.PathProv -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $pathRoot -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-WorkLabProvider dispatch' {
    It 'routes to the provider module and returns its result' {
        Register-WorkLabProvider -Name Faker -Options @{ Server = 'fake.lan' } | Out-Null
        # Core Test-WorkLabProvider dispatches to the provider's
        # Test-WorkLabProviderConnection (the contract cmdlet is nouned, so it
        # no longer collides with this core entrypoint).
        $r = Test-WorkLabProvider -Name Faker
        $r.Provider | Should -Be 'Faker'
        $r.Healthy | Should -BeTrue
        $r.EchoedOptions.Server | Should -Be 'fake.lan'
    }
}

Describe 'Test-WorkLabSlugCollision provider path' {
    It 'enumerates existing VMs via the dispatched provider' {
        Register-WorkLabProvider -Name Faker -Options @{ Server = 'fake.lan' } | Out-Null
        { Test-WorkLabSlugCollision -Slug faker -Role dc -ProviderName Faker } |
            Should -Throw -ExpectedMessage '*collides*'
    }
}
