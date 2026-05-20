# WorkLab

Provider-agnostic Windows lab framework. Define labs as version-controlled
PowerShell recipes; provision them on Proxmox, Hyper-V, or VMware through a
common provider contract.

> **Status: Phase 2.5** — guest-channel rails. The provider contract grows
> from 20 → 24 cmdlets (Test/Invoke/Write/Read GuestAgent/Command/File).
> `Build-WorkLabImage` takes a `-VirtioWinIso` and bakes the virtio
> storage/NIC drivers + qemu-guest-agent MSI into the image with a
> FirstLogonCommand that installs the agent **before** sysprep — closing the
> chicken-and-egg around reaching guests on isolated per-lab VNets.
> `Initialize-Lab` now waits for the guest agent post-clone and reports
> `GuestAgentReachable` per computer. Core gains `Invoke-WorkLabDscResource`
> (push a small script via the guest channel, run Test → Set if needed →
> Test, read JSON back) so any DSC resource on any provider works through one
> universal seam. Role-specific DSC modules (ActiveDirectoryDsc, etc.) ship
> with the recipes that need them, not pre-built into the framework.
> Proxmox provider implements the 4 new contract cmdlets REAL via
> qemu-guest-agent; Hyper-V (Phase 7) and VMware (Phase 8) remain stubs.

## Quickstart

```bash
git clone <repo> WorkLab && cd WorkLab
pwsh ./build.ps1                 # resolve deps, build all modules, analyze, unit test
pwsh ./build.ps1 -Tasks test     # analyzer + unit tests only
pwsh ./build.ps1 -Tasks integration   # gated; skips unless WORKLAB_PROXMOX_TEST_HOST set
```

`build.ps1` resolves build dependencies into `output/RequiredModules` (added
to `PSModulePath`), then drives Invoke-Build tasks that iterate every module
under `source/`.

### Try the framework

```powershell
Import-Module ./source/WorkLab/WorkLab.psd1
Import-Module ./source/WorkLab.Proxmox/WorkLab.Proxmox.psd1

Get-WorkLabRecipe -Type lab                      # discovery seam (in-tree)
Import-WorkLabRecipe -Name helloworld -Type lab

Register-WorkLabProvider -Name Proxmox -Options @{
    Server = 'pve.lab.local'; Zone = 'labzone'; ApiToken = 'svc@pve!worklab=<uuid>'
}
Test-WorkLabProvider -Name Proxmox               # real Proxmox health check
```

Secrets require a SecretManagement vault **you** register (WorkLab is
vault-agnostic):

```powershell
New-WorkLabSecret -Slug helloworld -Role local-admin -Name dc01 -Secret $cred
Get-WorkLabSecret -Slug helloworld -Role local-admin -Name dc01
```

## Layout

```
source/      WorkLab (core) + WorkLab.Proxmox/.HyperV/.VMware + WorkLabDsc
recipes/     labs/ topologies/ components/ apps/
tests/       Unit/ (Pester 5) + Integration/ (gated)
docs/        ARCHITECTURE, PROVIDERS, RECIPES, DECISIONS
.build/      Invoke-Build task files
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — decisions, module map, composition model
- [docs/PROVIDERS.md](docs/PROVIDERS.md) — provider contract + how to write a provider
- [docs/RECIPES.md](docs/RECIPES.md) — recipe types, discovery seam, worked example
- [docs/DECISIONS.md](docs/DECISIONS.md) — anti-patterns and why we don't do X
- [CONTRIBUTING.md](CONTRIBUTING.md) — module/test/CI conventions

## Phased build plan

| Phase | Scope |
|---|---|
| 0 ✅ | Skeleton, build/CI, core REAL pieces, contract stubs, Proxmox network ops + 1 integration test |
| 1 ✅ | Proxmox provider full implementation (VM/ISO/template/snapshots) via PSProxmoxVE |
| 2 ✅ | `Build-WorkLabImage` (DISM WIM patching) + first single-DC lab (DSC → Phase 2.5) |
| 2.5 ✅ | Guest channel: contract +4 cmdlets, image-baked virtio + qemu-ga, `Invoke-WorkLabDscResource` over provider seam |
| 3 | VyOS egress firewall (template build, per-lab render, deploy) |
| 4 | WSUS recipe (optional, gated, UpdateServicesDsc) |
| 5 | Multi-DC → multi-domain → multi-forest+trust → workgroup-host hybrid |
| 6 | App recipe primitives + first real app recipe |
| 7 | Hyper-V provider implementation |
| 8 | VMware provider implementation |

## Requirements

PowerShell 7+. Build resolves: InvokeBuild, Pester 5, PSScriptAnalyzer,
Sampler, PSFramework, Microsoft.PowerShell.SecretManagement, PSProxmoxVE.
