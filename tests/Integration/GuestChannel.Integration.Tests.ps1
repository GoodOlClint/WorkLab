# Gated Phase 2.5 end-to-end: image build with -VirtioWinIso → real Proxmox
# lab → guest agent reachable → Invoke-WorkLabDscResource against the built-in
# File resource → read the file back via Read-WorkLabProviderGuestFile → tear
# down. Exercises every Phase 2.5 surface in one shot. Self-skips unless ALL
# of: Windows host (DISM), source Windows ISO, virtio-win ISO, real Proxmox.
# Not runnable on the macOS dev box by design.
#
# Required env:
#   WORKLAB_IMG_TEST_SOURCE_ISO        path to a Windows ISO
#   WORKLAB_VIRTIO_ISO                 path to virtio-win.iso
#   WORKLAB_PROXMOX_TEST_HOST          Proxmox host/FQDN
#   WORKLAB_PROXMOX_TEST_TOKEN         API token  user@realm!tokenid=uuid
#   WORKLAB_PROXMOX_TEST_NODE          target node
#   WORKLAB_PROXMOX_TEST_DISK_STORAGE  VM disk storage
#   WORKLAB_PROXMOX_TEST_ISO_STORAGE   ISO storage
#   WORKLAB_PROXMOX_TEST_ZONE          pre-created SDN VLAN zone
# Optional: WORKLAB_PROXMOX_TEST_PORT (default 8006)

$script:GcGate = $IsWindows -and
    -not [string]::IsNullOrWhiteSpace($env:WORKLAB_IMG_TEST_SOURCE_ISO) -and
    -not [string]::IsNullOrWhiteSpace($env:WORKLAB_VIRTIO_ISO) -and
    -not [string]::IsNullOrWhiteSpace($env:WORKLAB_PROXMOX_TEST_HOST)

Describe 'Phase 2.5 guest channel end-to-end (gated)' -Skip:(-not $script:GcGate) {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force

        $script:Img = 'gcimg'
        $script:Slug = 'gc' + (-join ((48..57 + 97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
        $script:Cred = [pscredential]::new('Administrator',
            (ConvertTo-SecureString ('P@' + [guid]::NewGuid().ToString('N').Substring(0, 12)) -AsPlainText -Force))

        # Side-loaded single-DC recipe set pointing at the test image.
        $script:RecipeDir = Join-Path ([IO.Path]::GetTempPath()) "wl-gc-$([guid]::NewGuid().ToString('N'))"
        foreach ($sub in 'labs', 'topologies', 'components') {
            New-Item -ItemType Directory -Force -Path (Join-Path $script:RecipeDir $sub) | Out-Null
        }
        Set-Content (Join-Path $script:RecipeDir "labs/$($script:Slug).lab.psd1") `
            "@{ Schema='worklab.lab/v1'; Slug='$($script:Slug)'; Topology='gc-single' }"
        Set-Content (Join-Path $script:RecipeDir 'topologies/gc-single.topology.psd1') `
            "@{ Schema='worklab.topology/v1'; DomainControllers=@(@{ Component='gcdc'; Count=1 }) }"
        Set-Content (Join-Path $script:RecipeDir 'components/gcdc.component.psd1') `
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

        $script:DcVm = "lab-$($script:Slug)-dc01"
        $script:GuestPath = 'C:\worklab-gc-test.txt'
        $script:GuestContents = "hello from worklab phase 2.5 $([guid]::NewGuid().ToString('N'))"
    }

    AfterAll {
        try { Remove-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Remove-WorkLabImage -Name $script:Img -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        Remove-Item env:WORKLAB_RECIPE_PATH -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $script:RecipeDir -ErrorAction SilentlyContinue
    }

    It 'builds an image with virtio drivers + qemu-ga staged' {
        $img = Build-WorkLabImage -Name $script:Img `
            -SourceIso $env:WORKLAB_IMG_TEST_SOURCE_ISO `
            -VirtioWinIso $env:WORKLAB_VIRTIO_ISO `
            -AdminCredential $script:Cred -Confirm:$false
        Test-Path $img.IsoPath | Should -BeTrue
        $img.Manifest.virtioSha256 | Should -Match '^[0-9a-f]{64}$'
        $img.Manifest.guestAgentPath | Should -Match 'qemu-ga'
    }

    It 'initializes the lab and the guest agent becomes reachable' {
        $lab = Initialize-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false
        $lab.Slug | Should -Be $script:Slug
        @($lab.Computers).Count | Should -Be 1
        $lab.Computers[0].Name | Should -Be $script:DcVm
        # Build-into-the-image of qemu-ga + virtio means the agent comes up on
        # first boot; Initialize-Lab's Wait-WorkLabProviderGuestAgentReady must
        # see it within the default 600s window.
        $lab.Computers[0].GuestAgentReachable | Should -BeTrue
    }

    It 'applies a built-in File DSC resource over the guest channel' {
        $r = InModuleScope WorkLab -Parameters @{
            Slug = $script:Slug; VmName = $script:DcVm
            Path = $script:GuestPath; Contents = $script:GuestContents
        } {
            param($Slug, $VmName, $Path, $Contents)
            $reg = Get-WorkLabProvider -Name Proxmox
            $pctx = New-WorkLabProviderContext -Provider $reg -Slug $Slug
            Invoke-WorkLabDscResource -Provider $reg -Context $pctx -VmName $VmName `
                -ModuleName 'PSDesiredStateConfiguration' -ResourceName 'File' -Property @{
                    DestinationPath = $Path
                    Contents        = $Contents
                    Ensure          = 'Present'
                    Type            = 'File'
                }
        }

        $r.VmName | Should -Be $script:DcVm
        $r.ResourceName | Should -Be 'File'
        $r.Error | Should -BeNullOrEmpty
        $r.InDesiredStateAfter | Should -BeTrue
    }

    It 'reads the just-written file back via the guest channel' {
        $read = InModuleScope WorkLab -Parameters @{
            Slug = $script:Slug; VmName = $script:DcVm; Path = $script:GuestPath
        } {
            param($Slug, $VmName, $Path)
            $reg = Get-WorkLabProvider -Name Proxmox
            $pctx = New-WorkLabProviderContext -Provider $reg -Slug $Slug
            Invoke-WorkLabProviderCommand -Provider $reg -Verb 'Read' -Noun 'GuestFile' `
                -Arguments @{ Context = $pctx; VmName = $VmName; Path = $Path }
        }
        $read.Path    | Should -Be $script:GuestPath
        $read.Content | Should -Match ([regex]::Escape($script:GuestContents))
    }

    It 'tears the lab down cleanly' {
        $rm = Remove-Lab -LabRecipe $script:Slug -ProviderName Proxmox -Confirm:$false
        $rm.NetworkRemoved | Should -BeTrue
        Get-LabComputer -LabRecipe $script:Slug -ProviderName Proxmox | Should -BeNullOrEmpty
    }
}
