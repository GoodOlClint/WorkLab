# Gated image-pipeline + lab-orchestration integration test.
# Self-skips unless ALL of: running on Windows (DISM), a source Windows ISO,
# and a real Proxmox target are available. NOT runnable on the macOS dev box
# by design (see docs/DECISIONS.md) — covered here only when fully provisioned.
#
# Required env:
#   WORKLAB_IMG_TEST_SOURCE_ISO        path to a Windows ISO (Windows host)
#   WORKLAB_PROXMOX_TEST_HOST          Proxmox host/FQDN
#   WORKLAB_PROXMOX_TEST_TOKEN         API token  user@realm!tokenid=uuid
#   WORKLAB_PROXMOX_TEST_NODE          target node
#   WORKLAB_PROXMOX_TEST_DISK_STORAGE  VM disk storage
#   WORKLAB_PROXMOX_TEST_ISO_STORAGE   ISO storage
#   WORKLAB_PROXMOX_TEST_ZONE          pre-created SDN VLAN zone
# Optional: WORKLAB_PROXMOX_TEST_PORT (default 8006)

$script:ImgGate = $IsWindows -and
    -not [string]::IsNullOrWhiteSpace($env:WORKLAB_IMG_TEST_SOURCE_ISO) -and
    -not [string]::IsNullOrWhiteSpace($env:WORKLAB_PROXMOX_TEST_HOST)

Describe 'Image pipeline + single-DC lab (gated)' -Skip:(-not $script:ImgGate) {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force

        $script:Img = 'itimg'
        $script:Slug = 'it' + (-join ((48..57 + 97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
        $script:Cred = [pscredential]::new('Administrator',
            (ConvertTo-SecureString ('P@' + [guid]::NewGuid().ToString('N').Substring(0, 12)) -AsPlainText -Force))

        # Side-loaded single-DC recipe set pointing at the test image.
        $script:RecipeDir = Join-Path ([IO.Path]::GetTempPath()) "wl-ir-$([guid]::NewGuid().ToString('N'))"
        foreach ($sub in 'labs', 'topologies', 'components') {
            New-Item -ItemType Directory -Force -Path (Join-Path $script:RecipeDir $sub) | Out-Null
        }
        Set-Content (Join-Path $script:RecipeDir "labs/$($script:Slug).lab.psd1") `
            "@{ Schema='worklab.lab/v1'; Slug='$($script:Slug)'; Topology='it-single' }"
        Set-Content (Join-Path $script:RecipeDir 'topologies/it-single.topology.psd1') `
            "@{ Schema='worklab.topology/v1'; DomainControllers=@(@{ Component='itdc'; Count=1 }) }"
        Set-Content (Join-Path $script:RecipeDir 'components/itdc.component.psd1') `
            "@{ Schema='worklab.component/v1'; Role='dc'; Image='$($script:Img)' }"
        $env:WORKLAB_RECIPE_PATH = $script:RecipeDir

        Register-WorkLabProvider -Name Proxmox -Options @{
            Server               = $env:WORKLAB_PROXMOX_TEST_HOST
            Port                 = if ($env:WORKLAB_PROXMOX_TEST_PORT) { [int]$env:WORKLAB_PROXMOX_TEST_PORT } else { 8006 }
            ApiToken             = $env:WORKLAB_PROXMOX_TEST_TOKEN
            Node                 = $env:WORKLAB_PROXMOX_TEST_NODE
            DiskStorage          = $env:WORKLAB_PROXMOX_TEST_DISK_STORAGE
            IsoStorage           = $env:WORKLAB_PROXMOX_TEST_ISO_STORAGE
            Zone                 = $env:WORKLAB_PROXMOX_TEST_ZONE
            SkipCertificateCheck = $true
        } | Out-Null
    }

    AfterAll {
        try { Remove-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Remove-WorkLabImage -Name $script:Img -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        Remove-Item env:WORKLAB_RECIPE_PATH -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $script:RecipeDir -ErrorAction SilentlyContinue
    }

    It 'builds a patched image into the cache' {
        # WS2025 Standard GVLK (public) so the unattended install doesn't stop at
        # the product-key screen; override via WORKLAB_IMG_PRODUCT_KEY.
        $productKey = if ($env:WORKLAB_IMG_PRODUCT_KEY) { $env:WORKLAB_IMG_PRODUCT_KEY } else { 'TVRH6-WHNXV-R9WG3-9XRFY-MY832' }
        $img = Build-WorkLabImage -Name $script:Img -SourceIso $env:WORKLAB_IMG_TEST_SOURCE_ISO `
            -ProductKey $productKey `
            -AdminCredential $script:Cred -Confirm:$false
        Test-Path $img.IsoPath | Should -BeTrue
        $img.Manifest.isoSha256 | Should -Match '^[0-9a-f]{64}$'
        (Get-WorkLabImage -Name $script:Img).Name | Should -Be $script:Img
    }

    It 'initializes the single-DC lab and tears it down' {
        $lab = Initialize-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false
        $lab.Slug | Should -Be $script:Slug
        $lab.DscDeferred | Should -BeTrue
        @($lab.Computers).Count | Should -Be 1

        (Get-LabComputer -LabRecipe $script:Slug -ProviderName Proxmox).Name |
            Should -Contain "lab-$($script:Slug)-dc01"

        $rm = Remove-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false
        $rm.NetworkRemoved | Should -BeTrue
        Get-LabComputer -LabRecipe $script:Slug -ProviderName Proxmox | Should -BeNullOrEmpty
    }
}
