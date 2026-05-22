BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
    $script:Opt = @{ Server = 'p'; ApiToken = 't'; Node = 'n' }
}

Describe 'Export-WorkLabProviderTemplate' {
    It 'throws when the VM is absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }
            { Export-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-tpl01 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }

    It 'reconciles a VM that is already a template' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:nt = 0
            Mock New-PveTemplate -RemoveParameterType 'Session' { $script:nt++ }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                [pscustomobject]@{ Name = 'lab-demo-tpl01'; VmId = 9100; Status = 'stopped' }
            }
            $r = Export-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-tpl01 -Confirm:$false
            $r.IsTemplate | Should -BeTrue
            $r.Existed | Should -BeTrue
            $script:nt | Should -Be 0
        }
    }

    It 'stops a running VM and converts it' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:converted = $false
            $script:stopped = 0
            Mock Stop-PveVm -RemoveParameterType 'Session' { $script:stopped++ }
            Mock New-PveTemplate -RemoveParameterType 'Session' { $script:converted = $true }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($TemplatesOnly) {
                    if ($script:converted) { [pscustomobject]@{ Name = 'lab-demo-tpl01'; VmId = 9100; Status = 'stopped' } }
                }
                else { [pscustomobject]@{ Name = 'lab-demo-tpl01'; VmId = 9100; Status = 'running' } }
            }
            $r = Export-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-tpl01 -Confirm:$false
            $script:stopped | Should -Be 1
            $script:converted | Should -BeTrue
            $r.IsTemplate | Should -BeTrue
            $r.Existed | Should -BeFalse
        }
    }
}

Describe 'Get/Remove-WorkLabProviderTemplate' {
    It 'lists templates filtered by name' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                [pscustomobject]@{ Name = 'lab-demo-tpl01'; VmId = 9100 }
                [pscustomobject]@{ Name = 'lab-demo-tpl02'; VmId = 9101 }
            }
            $r = Get-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -Name lab-demo-tpl02
            ($r | Measure-Object).Count | Should -Be 1
            $r.IsTemplate | Should -BeTrue
            $r.Name | Should -Be 'lab-demo-tpl02'
        }
    }

    It 'removes when present and no-ops when absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:rmt = 0
            Mock Remove-PveTemplate -RemoveParameterType 'Session' { $script:rmt++ }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-tpl01'; VmId = 9100 } }
            (Remove-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -Name lab-demo-tpl01 -Confirm:$false).Removed | Should -BeTrue
            $script:rmt | Should -Be 1

            Mock Get-PveVm -RemoveParameterType 'Session' { }
            (Remove-WorkLabProviderTemplate -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -Name gone -Confirm:$false).Removed | Should -BeFalse
            $script:rmt | Should -Be 1
        }
    }
}

Describe 'Copy-WorkLabProviderVm' {
    It 'reconciles when the target already exists' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:clone = 0
            Mock New-PveVmFromTemplate -RemoveParameterType 'Session' { $script:clone++ }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if (-not $TemplatesOnly) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            }
            $r = Copy-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -TemplateName lab-base-tpl01 -VmName lab-demo-dc01 -Confirm:$false
            $r.Existed | Should -BeTrue
            $script:clone | Should -Be 0
        }
    }

    It 'throws when the template is missing' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }   # no target, no templates
            { Copy-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -TemplateName lab-base-tpl01 -VmName lab-demo-dc01 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Template*not found*'
        }
    }

    It 'full-clones from the template when target absent and enables the guest agent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:cloned = $false
            Mock New-PveVmFromTemplate -RemoveParameterType 'Session' { $script:cloned = $true }
            $script:cfg = $null
            Mock Set-PveVmConfig -RemoveParameterType 'Session' { $script:cfg = $AdditionalConfig }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($TemplatesOnly) { [pscustomobject]@{ Name = 'lab-base-tpl01'; VmId = 9000 } }
                elseif ($script:cloned) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            }
            # No Slug -> no net0 re-NIC, but the agent must still be enabled
            # (Proxmox returns "No QEMU guest agent configured" otherwise).
            $r = Copy-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -TemplateName lab-base-tpl01 -VmName lab-demo-dc01 -Confirm:$false
            $script:cloned | Should -BeTrue
            $r.Existed | Should -BeFalse
            $r.Name | Should -Be 'lab-demo-dc01'
            $script:cfg.agent | Should -Be '1'
            $script:cfg.Keys | Should -Not -Contain 'net0'
            # Install CD emptied (template's sata0 ISO is deleted post-build).
            $script:cfg.sata0 | Should -Be 'none,media=cdrom'
        }
    }

    It 're-NICs to the per-lab VNet AND enables the agent when Slug is present' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:cloned = $false
            Mock New-PveVmFromTemplate -RemoveParameterType 'Session' { $script:cloned = $true }
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { [pscustomobject]@{ Vnet = 'lXXXXXXX' } }
            $script:cfg = $null
            Mock Set-PveVmConfig -RemoveParameterType 'Session' { $script:cfg = $AdditionalConfig }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($TemplatesOnly) { [pscustomobject]@{ Name = 'lab-base-tpl01'; VmId = 9000 } }
                elseif ($script:cloned) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            }
            Copy-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -TemplateName lab-base-tpl01 -VmName lab-demo-dc01 -Confirm:$false | Out-Null
            $script:cfg.agent | Should -Be '1'
            $script:cfg.net0  | Should -Match 'bridge='
            $script:cfg.sata0 | Should -Be 'none,media=cdrom'
        }
    }
}
