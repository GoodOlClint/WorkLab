BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
    $script:Opt = @{ Server = 'p'; ApiToken = 't'; Node = 'n' }
}

Describe 'Test-WorkLabProviderGuestAgent' {
    It 'returns Reachable=$false when the VM is absent' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }
            Mock Test-PveVmGuestAgent -RemoveParameterType 'Session' { $true }
            $r = Test-WorkLabProviderGuestAgent -Context @{ Options = $Opt } -VmName lab-x-dc01
            $r.Reachable | Should -BeFalse
            Should -Invoke Test-PveVmGuestAgent -Times 0
        }
    }
    It 'returns Reachable=$true when the agent answers' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-x-dc01'; VmId = 9100 } }
            Mock Test-PveVmGuestAgent -RemoveParameterType 'Session' { $true }
            $r = Test-WorkLabProviderGuestAgent -Context @{ Options = $Opt } -VmName lab-x-dc01
            $r.Reachable | Should -BeTrue
            $r.Provider | Should -Be 'Proxmox'
        }
    }
    It 'returns Reachable=$false (no throw) when the agent call errors' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-x-dc01'; VmId = 9100 } }
            Mock Test-PveVmGuestAgent -RemoveParameterType 'Session' { throw 'guest-agent not running' }
            (Test-WorkLabProviderGuestAgent -Context @{ Options = $Opt } -VmName lab-x-dc01).Reachable | Should -BeFalse
        }
    }
}

Describe 'Invoke-WorkLabProviderGuestCommand' {
    It 'normalizes ExitCode/Stdout/Stderr/Pid from PSProxmoxVE' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-x-dc01'; VmId = 9100 } }
            Mock Invoke-PveVmGuestExec -RemoveParameterType 'Session' {
                [pscustomobject]@{ ExitCode = 0; Stdout = 'hello'; Stderr = ''; Pid = 1234 }
            }
            $r = Invoke-WorkLabProviderGuestCommand -Context @{ Options = $Opt } -VmName lab-x-dc01 `
                -Command pwsh -Arguments '-NoProfile', '-Command', 'Write-Output hello'
            $r.ExitCode | Should -Be 0
            $r.Stdout | Should -Be 'hello'
            $r.Pid | Should -Be 1234
        }
    }
    It 'throws teaching error when VM absent' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }
            { Invoke-WorkLabProviderGuestCommand -Context @{ Options = $Opt } -VmName lab-x-dc01 -Command pwsh } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}

Describe 'Write/Read-WorkLabProviderGuestFile' {
    It 'Write reports Bytes; Read returns Content; both throw when VM absent' {
        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-x-dc01'; VmId = 9100 } }
            $script:written = $null
            Mock Write-PveVmGuestFile -RemoveParameterType 'Session' { $script:written = $Content }
            Mock Read-PveVmGuestFile -RemoveParameterType 'Session' { 'the-content' }

            $w = Write-WorkLabProviderGuestFile -Context @{ Options = $Opt } -VmName lab-x-dc01 `
                -Path 'C:\Windows\Temp\x.txt' -Content 'hello world' -Confirm:$false
            $w.Bytes | Should -Be 11
            $script:written | Should -Be 'hello world'

            (Read-WorkLabProviderGuestFile -Context @{ Options = $Opt } -VmName lab-x-dc01 `
                -Path 'C:\Windows\Temp\x.txt').Content | Should -Be 'the-content'
        }

        InModuleScope WorkLab.Proxmox -Parameters @{ Opt = $script:Opt } {
            param($Opt)
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }
            { Write-WorkLabProviderGuestFile -Context @{ Options = $Opt } -VmName lab-x-dc01 `
                  -Path 'C:\x' -Content 'y' -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'
            { Read-WorkLabProviderGuestFile -Context @{ Options = $Opt } -VmName lab-x-dc01 `
                  -Path 'C:\x' } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}
