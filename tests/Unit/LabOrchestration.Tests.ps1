BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Lab orchestration (provider dispatch + discovery seam mocked)' {
    BeforeEach {
        InModuleScope WorkLab {
            $prov = [pscustomobject]@{ Name = 'Proxmox'; ModuleName = 'WorkLab.Proxmox'; Options = @{ Server = 'p' } }
            $standin = [pscustomobject]@{ Slug = 'helloworld'; Provider = $prov }
            $standin | Add-Member ScriptMethod VmName { param($r, $n) '{0}-{1}{2:D2}' -f "lab-$($this.Slug)", $r, $n }
            $standin | Add-Member ScriptMethod ComputerName { param($r, $n) '{0}-{1}{2:D2}' -f $this.Slug.ToUpper(), $r.ToUpper(), $n }
            $script:Ctx = $standin

            Mock New-WorkLabContextFromRecipe { $script:Ctx }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'lab' } {
                [pscustomobject]@{ Data = @{ Slug = 'helloworld'; Topology = 'single-domain' } }
            }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'topology' } {
                [pscustomobject]@{ Data = @{ DomainControllers = @(@{ Component = 'dc'; Count = 1 }) } }
            }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'component' } {
                [pscustomobject]@{ Data = @{ Role = 'dc'; Image = 'ws2025-core' } }
            }
            Mock New-WorkLabImageTemplate { [pscustomobject]@{ ImageName = $ImageName; TemplateName = 'lab-imgbabcdefgh-tpl01'; Existed = $true } }
            $script:calls = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                $script:calls.Add("$Verb-$Noun")
                if ($Verb -eq 'Get' -and $Noun -eq 'Vm') {
                    return @(
                        [pscustomobject]@{ Name = 'lab-helloworld-dc01'; Status = 'running' }
                    )
                }
                if ($Verb -eq 'Remove' -and $Noun -eq 'Network') { return [pscustomobject]@{ Removed = $true } }
                if ($Verb -eq 'Invoke' -and $Noun -eq 'GuestCommand') {
                    # Guest-ready probe: report Windows setup complete.
                    return [pscustomobject]@{ ExitCode = 0; Stdout = 'ImageState REG_SZ IMAGE_STATE_COMPLETE'; Stderr = '' }
                }
            }
        }
    }

    It 'Initialize-Lab ensures network, template, then clones each computer' {
        InModuleScope WorkLab {
            $r = Initialize-Lab -LabRecipe helloworld -ProviderName Proxmox -Confirm:$false
            $r.Slug | Should -Be 'helloworld'
            $r.DscDeferred | Should -BeTrue
            @($r.Computers).Count | Should -Be 1
            $r.Computers[0].Name | Should -Be 'lab-helloworld-dc01'
            $r.Computers[0].Template | Should -Be 'lab-imgbabcdefgh-tpl01'
            $r.Computers[0].GuestAgentReachable | Should -BeTrue
            Should -Invoke New-WorkLabImageTemplate -Times 1
            $script:calls[0] | Should -Be 'New-Network'
            $script:calls | Should -Contain 'Copy-Vm'
            $script:calls | Should -Contain 'Invoke-GuestCommand'
        }
    }

    It 'Remove-Lab removes every VM then the network' {
        InModuleScope WorkLab {
            $r = Remove-Lab -LabRecipe helloworld -ProviderName Proxmox -Confirm:$false
            $r.Removed | Should -Contain 'lab-helloworld-dc01'
            $r.NetworkRemoved | Should -BeTrue
            $script:calls | Should -Contain 'Get-Vm'
            $script:calls | Should -Contain 'Remove-Vm'
            $script:calls.IndexOf('Remove-Vm') | Should -BeLessThan $script:calls.LastIndexOf('Remove-Network')
        }
    }

    It 'Get-Lab returns slug/provider/computers' {
        InModuleScope WorkLab {
            $r = Get-Lab -LabRecipe helloworld -ProviderName Proxmox
            $r.Slug | Should -Be 'helloworld'
            $r.Provider | Should -Be 'Proxmox'
            $r.Computers[0].Name | Should -Be 'lab-helloworld-dc01'
        }
    }

    It 'Get-LabComputer filters by name' {
        InModuleScope WorkLab {
            (Get-LabComputer -LabRecipe helloworld -ProviderName Proxmox -Name lab-helloworld-dc01).Name |
                Should -Be 'lab-helloworld-dc01'
            Get-LabComputer -LabRecipe helloworld -ProviderName Proxmox -Name nope | Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-WorkLabComputerPlan validation' {
    It 'throws when the topology has no DomainControllers group' {
        InModuleScope WorkLab {
            $prov = [pscustomobject]@{ Name = 'Proxmox'; Options = @{} }
            $standin = [pscustomobject]@{ Slug = 'demo'; Provider = $prov }
            $standin | Add-Member ScriptMethod VmName { param($r, $n) "lab-demo-$r$n" }
            $standin | Add-Member ScriptMethod ComputerName { param($r, $n) "DEMO-$r$n" }
            Mock New-WorkLabContextFromRecipe { $standin }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'lab' } { [pscustomobject]@{ Data = @{ Topology = 't' } } }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'topology' } { [pscustomobject]@{ Data = @{} } }
            { Resolve-WorkLabComputerPlan -LabRecipe demo -ProviderName Proxmox } |
                Should -Throw -ExpectedMessage '*DomainControllers*'
        }
    }
    It 'throws when a component has no Image' {
        InModuleScope WorkLab {
            $prov = [pscustomobject]@{ Name = 'Proxmox'; Options = @{} }
            $standin = [pscustomobject]@{ Slug = 'demo'; Provider = $prov }
            $standin | Add-Member ScriptMethod VmName { param($r, $n) "lab-demo-$r$n" }
            $standin | Add-Member ScriptMethod ComputerName { param($r, $n) "DEMO-$r$n" }
            Mock New-WorkLabContextFromRecipe { $standin }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'lab' } { [pscustomobject]@{ Data = @{ Topology = 't' } } }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'topology' } { [pscustomobject]@{ Data = @{ DomainControllers = @(@{ Component = 'dc'; Count = 1 }) } } }
            Mock Import-WorkLabRecipe -ParameterFilter { $Type -eq 'component' } { [pscustomobject]@{ Data = @{ Role = 'dc' } } }
            { Resolve-WorkLabComputerPlan -LabRecipe demo -ProviderName Proxmox } |
                Should -Throw -ExpectedMessage '*no ''Image''*'
        }
    }
}
