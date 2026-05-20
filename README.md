# WorkLab

Provider-agnostic Windows lab framework. Define labs as version-controlled
PowerShell recipes; provision them on Proxmox, Hyper-V, or VMware through a
common provider contract.

> **Status: Phase 2** — adds the `Build-WorkLabImage` DISM WIM-patch pipeline
> (Windows-only; mocked on non-Windows), an image cache, a lazy hybrid
> template cache (ephemeral build network), and REAL
> `Initialize-Lab`/`Remove-Lab`/`Get-Lab`/`Get-LabComputer` orchestration that
> stands up the single-DC `helloworld` lab on the Proxmox provider. ADDS DSC
> promotion is **deferred to Phase 2.5** (guest reachability on the isolated
> per-lab VNet is unresolved). On Phase 1: fully implemented Proxmox provider.
> Hyper-V/VMware remain contract stubs.
>
> **Verification note:** the DISM/boot/sysprep path is Windows-only and
> **cannot be exercised on the macOS dev box** — it is covered by mocked
> unit tests plus a gated integration test that self-skips without a Windows
> host + Proxmox + Windows ISO.

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
| 2.5 | ADDS DSC promotion via `Invoke-DscResource`; resolve guest reachability on the isolated per-lab VNet |
| 3 | VyOS egress firewall (template build, per-lab render, deploy) |
| 4 | WSUS recipe (optional, gated, UpdateServicesDsc) |
| 5 | Multi-DC → multi-domain → multi-forest+trust → workgroup-host hybrid |
| 6 | App recipe primitives + first real app recipe |
| 7 | Hyper-V provider implementation |
| 8 | VMware provider implementation |

## Requirements

PowerShell 7+. Build resolves: InvokeBuild, Pester 5, PSScriptAnalyzer,
Sampler, PSFramework, Microsoft.PowerShell.SecretManagement, PSProxmoxVE.
