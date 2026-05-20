BeforeAll {
    $script:SrcRoot = Join-Path $PSScriptRoot '../../source'
    Import-Module (Join-Path $script:SrcRoot 'WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
    Import-Module (Join-Path $script:SrcRoot 'WorkLab.HyperV/WorkLab.HyperV.psd1') -Force
    Import-Module (Join-Path $script:SrcRoot 'WorkLab.VMware/WorkLab.VMware.psd1') -Force

    # All providers export identically-named contract cmdlets, so the global
    # command table is shadowed by load order. Resolve per-module via the
    # module object's ExportedCommands — exactly how core dispatch works.
    $script:Contract = @(
        'Test-WorkLabProviderConnection'
        'New-WorkLabProviderNetwork', 'Remove-WorkLabProviderNetwork', 'Get-WorkLabProviderNetwork'
        'New-WorkLabProviderIso', 'Get-WorkLabProviderIso', 'Remove-WorkLabProviderIso'
        'Export-WorkLabProviderTemplate', 'Get-WorkLabProviderTemplate', 'Remove-WorkLabProviderTemplate'
        'New-WorkLabProviderVm', 'Copy-WorkLabProviderVm', 'Get-WorkLabProviderVm'
        'Start-WorkLabProviderVm', 'Stop-WorkLabProviderVm', 'Remove-WorkLabProviderVm'
        'Checkpoint-WorkLabProviderVm', 'Restore-WorkLabProviderVm'
        'Get-WorkLabProviderCheckpoint', 'Remove-WorkLabProviderCheckpoint'
        # Phase 2.5 guest channel (4 new cmdlets)
        'Test-WorkLabProviderGuestAgent'
        'Invoke-WorkLabProviderGuestCommand'
        'Write-WorkLabProviderGuestFile'
        'Read-WorkLabProviderGuestFile'
    )
}

Describe 'Provider contract surface' -ForEach @(
    @{ Module = 'WorkLab.Proxmox' }
    @{ Module = 'WorkLab.HyperV' }
    @{ Module = 'WorkLab.VMware' }
) {
    It '<Module> exports all 24 contract cmdlets, each taking -Context' {
        $exported = (Get-Module $Module).ExportedCommands
        $exported.Count | Should -Be 24
        foreach ($name in $script:Contract) {
            $cmd = $exported[$name]
            $cmd | Should -Not -BeNullOrEmpty -Because "$Module must export $name"
            $cmd.Parameters.Keys | Should -Contain 'Context'
        }
    }
}

Describe 'Stubs throw NotImplementedException' {
    # Proxmox has no stubs left after Phase 1; remaining stubs are HyperV
    # (Phase 7) and VMware (Phase 8).
    It '<Provider> <Cmdlet> (Phase <Phase>) throws NotImplementedException' -ForEach @(
        @{ Provider = 'WorkLab.HyperV';  Cmdlet = 'New-WorkLabProviderVm'; Phase = 7 }
        @{ Provider = 'WorkLab.HyperV';  Cmdlet = 'Test-WorkLabProviderConnection';  Phase = 7 }
        @{ Provider = 'WorkLab.HyperV';  Cmdlet = 'Test-WorkLabProviderGuestAgent';  Phase = 7 }
        @{ Provider = 'WorkLab.VMware';  Cmdlet = 'New-WorkLabProviderNetwork'; Phase = 8 }
        @{ Provider = 'WorkLab.VMware';  Cmdlet = 'Invoke-WorkLabProviderGuestCommand'; Phase = 8 }
    ) {
        $cmd = (Get-Module $Provider).ExportedCommands[$Cmdlet]
        { & $cmd -Context @{ Options = @{} } } |
            Should -Throw -ExceptionType ([System.NotImplementedException])
    }
}

Describe 'Proxmox network identity (REAL helper)' {
    It 'is deterministic and obeys Proxmox VNet + VLAN constraints' {
        $a = & (Get-Module WorkLab.Proxmox) { Get-WorkLabProxmoxNetworkIdentity -Slug 'twoforest' }
        $b = & (Get-Module WorkLab.Proxmox) { Get-WorkLabProxmoxNetworkIdentity -Slug 'twoforest' }
        $a.Vnet | Should -Be $b.Vnet
        $a.Tag  | Should -Be $b.Tag
        $a.Vnet.Length | Should -BeLessOrEqual 8
        $a.Vnet | Should -Match '^[a-z][a-z0-9]*$'
        $a.Tag | Should -BeGreaterOrEqual 100
        $a.Tag | Should -BeLessOrEqual 200
    }
    It 'honors a custom VLAN pool' {
        $id = & (Get-Module WorkLab.Proxmox) { Get-WorkLabProxmoxNetworkIdentity -Slug 'demo' -PoolStart 300 -PoolEnd 305 }
        $id.Tag | Should -BeGreaterOrEqual 300
        $id.Tag | Should -BeLessOrEqual 305
    }
}
