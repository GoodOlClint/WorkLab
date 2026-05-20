BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Secret vault fast-fail' {
    It 'throws a teaching error when no vault is registered' {
        Mock -ModuleName WorkLab Get-SecretVault { @() }
        { New-WorkLabSecret -Slug demo -Role local-admin -Name dc01 -Secret 'p' } |
            Should -Throw -ExpectedMessage '*Register-SecretVault*'
    }
}

Describe 'New/Get/Remove-WorkLabSecret' {
    BeforeEach {
        # Capture the resolved secret name in the mock body rather than via
        # Should -Invoke -ParameterFilter: filter re-binding against
        # SecretManagement's real command metadata is fragile across Pester
        # versions under StrictMode. The mock body is stable.
        $script:SetName = $null
        $script:GetName = $null
        $script:RemoveName = $null
        $script:RemoveVault = $null
        Mock -ModuleName WorkLab Get-SecretVault { [pscustomobject]@{ Name = 'V'; IsDefault = $true } }
        Mock -ModuleName WorkLab Set-Secret { $script:SetName = $Name }
        Mock -ModuleName WorkLab Get-Secret { $script:GetName = $Name; 'the-secret' }
        Mock -ModuleName WorkLab Get-SecretInfo { [pscustomobject]@{ Name = $Name; VaultName = 'V' } }
        Mock -ModuleName WorkLab Remove-Secret { $script:RemoveName = $Name; $script:RemoveVault = $Vault }
    }

    It 'writes using the worklab/<slug>/<role>/<name> namespace' {
        $name = New-WorkLabSecret -Slug twoforest -Role local-admin -Name dc01 -Secret 'pw' -PassThru
        $name | Should -Be 'worklab/twoforest/local-admin/dc01'
        Should -Invoke -ModuleName WorkLab Set-Secret -Times 1
        $script:SetName | Should -Be 'worklab/twoforest/local-admin/dc01'
    }
    It 'reads the namespaced secret' {
        Get-WorkLabSecret -Slug twoforest -Role domain-admin -Name contoso.local | Should -Be 'the-secret'
        $script:GetName | Should -Be 'worklab/twoforest/domain-admin/contoso.local'
    }
    It 'removes from the discovered owning vault' {
        Remove-WorkLabSecret -Slug twoforest -Role svc -Name sql01 -Confirm:$false
        Should -Invoke -ModuleName WorkLab Remove-Secret -Times 1
        $script:RemoveName | Should -Be 'worklab/twoforest/svc/sql01'
        $script:RemoveVault | Should -Be 'V'
    }
    It 'rejects an invalid slug' {
        { New-WorkLabSecret -Slug 'Bad-Slug' -Role svc -Name x -Secret 'p' } | Should -Throw
    }
    It 'rejects a role containing a slash' {
        { New-WorkLabSecret -Slug demo -Role 'a/b' -Name x -Secret 'p' } |
            Should -Throw -ExpectedMessage '*no slashes*'
    }
}
