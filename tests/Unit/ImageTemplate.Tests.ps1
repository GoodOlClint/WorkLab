BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Get-WorkLabImageBuildSlug' {
    It 'is deterministic and a valid 12-char slug' {
        InModuleScope WorkLab {
            $a = Get-WorkLabImageBuildSlug -Name 'ws2025-core'
            $b = Get-WorkLabImageBuildSlug -Name 'ws2025-core'
            $a | Should -Be $b
            $a | Should -Match '^imgb[a-z0-9]{8}$'
            $a | Should -Match '^[a-z0-9]{3,12}$'
            (Get-WorkLabImageBuildSlug -Name 'other') | Should -Not -Be $a
        }
    }
}

Describe 'Wait-WorkLabProviderVmStopped' {
    It 'returns once the VM reports stopped' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' { [pscustomobject]@{ Name = 'lab-x-tpl01'; Status = 'stopped' } }
            { Wait-WorkLabProviderVmStopped -Provider @{} -Context @{} -VmName lab-x-tpl01 -TimeoutSeconds 5 } |
                Should -Not -Throw
        }
    }
    It 'throws if the VM disappears' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' { }
            { Wait-WorkLabProviderVmStopped -Provider @{} -Context @{} -VmName lab-x-tpl01 -TimeoutSeconds 5 } |
                Should -Throw -ExpectedMessage '*disappeared*'
        }
    }
    It 'throws on timeout while still running' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' { [pscustomobject]@{ Name = 'lab-x-tpl01'; Status = 'running' } }
            { Wait-WorkLabProviderVmStopped -Provider @{} -Context @{} -VmName lab-x-tpl01 -TimeoutSeconds 0 } |
                Should -Throw -ExpectedMessage '*Timed out*'
        }
    }
}

Describe 'New-WorkLabImageTemplate' {
    It 'reuses an existing template (hybrid cache hit)' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' -ParameterFilter { $Verb -eq 'Get' -and $Noun -eq 'Template' } {
                [pscustomobject]@{ Name = 'lab-imgbXXXXXXXX-tpl01' }
            }
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' -ParameterFilter { $Noun -eq 'Vm' } { throw 'should not build' }
            Mock Get-WorkLabImage { throw 'should not touch cache on a hit' }

            $r = New-WorkLabImageTemplate -Provider @{ Options = @{ Server = 'p' } } -ImageName ws -Confirm:$false
            $r.Existed | Should -BeTrue
        }
    }

    It 'throws when the image is not in the cache' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' -ParameterFilter { $Verb -eq 'Get' -and $Noun -eq 'Template' } { }
            Mock Get-WorkLabImage { }
            { New-WorkLabImageTemplate -Provider @{ Options = @{} } -ImageName ws -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Build it first*'
        }
    }

    It 'materializes via ephemeral network then tears it down' {
        InModuleScope WorkLab {
            $script:calls = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                $script:calls.Add("$Verb-$Noun")
                if ($Verb -eq 'Get' -and $Noun -eq 'Template') { return }
                if ($Verb -eq 'Get' -and $Noun -eq 'Vm') { return [pscustomobject]@{ Status = 'stopped' } }
            }
            Mock Get-WorkLabImage { [pscustomobject]@{ Name = 'ws'; IsoPath = '/cache/images/ws/ws.iso' } }

            $r = New-WorkLabImageTemplate -Provider @{ Options = @{ Server = 'p' } } -ImageName ws -Confirm:$false
            $r.Existed | Should -BeFalse
            $r.TemplateName | Should -Match '^lab-imgb[a-z0-9]{8}-tpl01$'
            $script:calls | Should -Contain 'New-Network'
            $script:calls | Should -Contain 'New-Iso'
            $script:calls | Should -Contain 'New-Vm'
            $script:calls | Should -Contain 'Export-Template'
            $script:calls | Should -Contain 'Remove-Network'
            # The uploaded install ISO is removed after the build (no leak).
            $script:calls | Should -Contain 'Remove-Iso'
            # Network created before VM, torn down after export.
            $script:calls.IndexOf('New-Network') | Should -BeLessThan $script:calls.IndexOf('New-Vm')
            $script:calls.IndexOf('Export-Template') | Should -BeLessThan ($script:calls.LastIndexOf('Remove-Network'))
        }
    }

    It 'tears the ephemeral network + ISO down even when the build fails' {
        InModuleScope WorkLab {
            $script:teardown = 0
            $script:isoRemoved = 0
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                if ($Verb -eq 'Get' -and $Noun -eq 'Template') { return }
                if ($Verb -eq 'New' -and $Noun -eq 'Vm') { throw 'boot failed' }
                if ($Verb -eq 'Remove' -and $Noun -eq 'Network') { $script:teardown++ }
                if ($Verb -eq 'Remove' -and $Noun -eq 'Iso') { $script:isoRemoved++ }
            }
            Mock Get-WorkLabImage { [pscustomobject]@{ Name = 'ws'; IsoPath = '/c/ws.iso' } }
            { New-WorkLabImageTemplate -Provider @{ Options = @{} } -ImageName ws -Confirm:$false } |
                Should -Throw -ExpectedMessage '*boot failed*'
            $script:teardown | Should -Be 1
            $script:isoRemoved | Should -Be 1
        }
    }
}
