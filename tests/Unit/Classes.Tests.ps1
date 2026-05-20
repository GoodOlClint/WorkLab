BeforeAll {
    $script:ClassDir = Join-Path $PSScriptRoot '../../source/WorkLab/Classes'
    # Dependency order (using module does not see runtime-dot-sourced classes).
    . (Join-Path $script:ClassDir 'RecipeReference.ps1')
    . (Join-Path $script:ClassDir 'ProviderRegistration.ps1')
    . (Join-Path $script:ClassDir 'LabContext.ps1')
}

Describe 'RecipeReference' {
    It 'exposes plain name when no namespace' {
        $r = [RecipeReference]::new('helloworld', 'lab', '/x/helloworld.lab.psd1', 'InTree')
        $r.QualifiedName() | Should -Be 'helloworld'
        "$r" | Should -Match '^helloworld \[lab\] \(InTree\)$'
    }
    It 'namespace-qualifies on collision' {
        $r = [RecipeReference]::new('dsp-install', 'app', '/m/dsp.psd1', 'Module')
        $r.Namespace = 'Semperis.WorkLab.Recipes'
        $r.QualifiedName() | Should -Be 'Semperis.WorkLab.Recipes/dsp-install'
    }
}

Describe 'ProviderRegistration' {
    It 'constructs and defaults options' {
        $p = [ProviderRegistration]::new('Proxmox', 'WorkLab.Proxmox', $null)
        $p.Name | Should -Be 'Proxmox'
        $p.Options | Should -BeOfType ([hashtable])
        $p.RegisteredAt | Should -BeOfType ([datetime])
    }
    It 'rejects empty name or module' {
        { [ProviderRegistration]::new('', 'WorkLab.Proxmox', @{}) } | Should -Throw
        { [ProviderRegistration]::new('Proxmox', '', @{}) } | Should -Throw
    }
}

Describe 'LabContext' {
    It 'validates slug format' {
        { [LabContext]::AssertValidSlug('twoforest') } | Should -Not -Throw
        { [LabContext]::AssertValidSlug('Two-Forest') } | Should -Throw
        { [LabContext]::AssertValidSlug('ab') } | Should -Throw
        { [LabContext]::AssertValidSlug('thisslugiswaytoolong') } | Should -Throw
    }
    It 'derives VM and computer names' {
        $c = [LabContext]::new('twoforest', $null, $null)
        $c.VmName('dc', 1) | Should -Be 'lab-twoforest-dc01'
        $c.ComputerName('dc', 1) | Should -Be 'TWOFOREST-DC01'
    }
    It 'enforces the 15-char NetBIOS limit' {
        $c = [LabContext]::new('twelvecharss', $null, $null)   # 12-char slug
        { $c.ComputerName('controller', 1) } | Should -Throw -ExpectedMessage '*NetBIOS*'
    }
    It 'builds namespaced secret paths' {
        $c = [LabContext]::new('twoforest', $null, $null)
        $c.SecretNamespace | Should -Be 'worklab/twoforest'
        $c.LocalAdminSecretPath('TWOFOREST-DC01') | Should -Be 'worklab/twoforest/local-admin/TWOFOREST-DC01'
        $c.DomainAdminSecretPath('contoso.local') | Should -Be 'worklab/twoforest/domain-admin/contoso.local'
        $c.ServiceAccountSecretPath('sql01') | Should -Be 'worklab/twoforest/svc/sql01'
    }
}
