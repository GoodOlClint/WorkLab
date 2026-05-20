# Gated Proxmox integration test: per-lab SDN VNet create -> get -> destroy.
# Self-skips unless WORKLAB_PROXMOX_TEST_HOST is set, so CI stays green
# without infrastructure.
#
# Required env:
#   WORKLAB_PROXMOX_TEST_HOST   Proxmox host/FQDN
#   WORKLAB_PROXMOX_TEST_TOKEN  API token  user@realm!tokenid=uuid
#   WORKLAB_PROXMOX_TEST_ZONE   pre-created SDN VLAN zone name
# Optional:
#   WORKLAB_PROXMOX_TEST_PORT   (default 8006)

# Evaluated at Pester discovery time for the -Skip expression.
$script:ProxmoxGate = -not [string]::IsNullOrWhiteSpace($env:WORKLAB_PROXMOX_TEST_HOST)

Describe 'Proxmox per-lab network lifecycle' -Skip:(-not $script:ProxmoxGate) {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force

        $script:Slug = 'it' + (-join ((48..57 + 97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
        $script:Ctx = @{
            Slug    = $script:Slug
            Options = @{
                Server               = $env:WORKLAB_PROXMOX_TEST_HOST
                Port                 = if ($env:WORKLAB_PROXMOX_TEST_PORT) { [int]$env:WORKLAB_PROXMOX_TEST_PORT } else { 8006 }
                ApiToken             = $env:WORKLAB_PROXMOX_TEST_TOKEN
                Zone                 = $env:WORKLAB_PROXMOX_TEST_ZONE
                SkipCertificateCheck = $true
            }
        }
    }

    AfterAll {
        try { Remove-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    It 'creates the per-lab SDN VNet (idempotent)' {
        $net = New-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false
        $net.Provider | Should -Be 'Proxmox'
        $net.Name | Should -Match '^[a-z][a-z0-9]{0,7}$'
        $net.Tag | Should -BeGreaterOrEqual 100
        $net.Tag | Should -BeLessOrEqual 200

        # Re-running reconciles, never duplicates.
        $again = New-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false
        $again.Existed | Should -BeTrue
        $again.Name | Should -Be $net.Name
    }

    It 'gets the per-lab network back' {
        $got = Get-WorkLabProviderNetwork -Context $script:Ctx
        $got | Should -Not -BeNullOrEmpty
        $got.Tag | Should -BeGreaterOrEqual 100
    }

    It 'removes the per-lab network and then reports absence' {
        $removed = Remove-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false
        $removed.Removed | Should -BeTrue
        Get-WorkLabProviderNetwork -Context $script:Ctx | Should -BeNullOrEmpty
    }
}
