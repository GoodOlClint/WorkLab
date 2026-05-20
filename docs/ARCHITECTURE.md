# WorkLab Architecture

WorkLab builds Windows labs across multiple hypervisors from version-controlled
PowerShell recipes. It is a single monorepo of cooperating modules with one
hard rule: **hypervisor knowledge lives only in `WorkLab.<Provider>` modules.**

## Settled decisions

These are firm. They are not reopened without an explicit decision record.

| Decision | Choice |
|---|---|
| Hypervisor abstraction | Provider plugins (common interface, swap implementation) |
| Lab definition format | PowerShell PSD1 hashtables |
| Repo structure | Single monorepo with multiple modules |
| Egress firewall | VyOS Stream (pinned ISO, version-controlled) |
| Windows install method | DISM WIM patching + hypervisor-native VM create + Sysprep capture (hybrid template cache) |
| Configuration application | DSC via `Invoke-DscResource` in method-call mode (no MOF, no pull server) |
| DSC version | DSC v2 (revisit v3 when ActiveDirectoryDsc/SqlServerDsc port) |
| Recipe model | PowerShell orchestrators composing framework primitives wrapping existing DSC resources |
| Lifecycle ops | Minimum verb set + snapshot ops |
| Identity scheme | Slug-prefix (`lab-${slug}-dc01`, `LAB${SLUG}-DC01`) |
| Provider build order | Proxmox → Hyper-V → VMware |
| Recipe file naming | `*.lab.psd1`, `*.topology.psd1`, `*.component.psd1`, app folder under `recipes/apps/` |
| Secret storage | `Microsoft.PowerShell.SecretManagement` only; vault-agnostic; user owns vault registration |
| Secret namespacing | `worklab/${labslug}/${role}/${secretname}` |
| Logging | PSFramework structured logging across all cmdlets |
| Within-lab network | Single subnet per lab; optional `Sites` for multi-subnet AD |
| Module naming | `WorkLab`, `WorkLab.Proxmox`, `WorkLab.HyperV`, `WorkLab.VMware`, `WorkLabDsc` |

## Module map

```
WorkLab            core: discovery seam, provider registry, secrets, logging,
                   lifecycle orchestration. ZERO hypervisor code.
WorkLab.Proxmox    provider: implements the contract on Proxmox (PSProxmoxVE).
WorkLab.HyperV     provider: implements the contract on Hyper-V.
WorkLab.VMware     provider: implements the contract on VMware.
WorkLabDsc         custom DSC composite resources (empty until Phase 5+).
```

## The flow object: `LabContext`

There is no module-scoped mutable lab state. A `LabContext` carries slug,
recipe reference, provider registration, secret namespace, and log channel,
and flows through every cmdlet as a parameter. The **only** module-scoped
mutable state is the provider registration table (managed solely via
`Register-WorkLabProvider` / `Get-WorkLabProvider`).

`LabContext` also computes identity so recipes never hardcode names:

- VM name (hypervisor): `lab-<slug>-<role><nn>` → `lab-twoforest-dc01`
- Computer name (Windows, ≤15 char NetBIOS): `<SLUG>-<ROLE><nn>` → `TWOFOREST-DC01`
- Secret paths: `worklab/<slug>/<role>/<name>`

Slugs are validated at the boundary: 3–12 chars, lowercase alphanumeric, no
hyphens. Invalid input fails fast with a teaching message.

## Composition model: recipe → topology → component → app

```
lab.psd1            top-level. Declares Slug, Provider mapping, and composes:
  └─ topology.psd1  reusable AD layout (forest/domain/DC counts, trusts, Sites)
       └─ component.psd1   single-host definition (OS SKU, role, base config)
  └─ apps/<App>/    app recipe modules run on computed hosts post-base-config
```

- **lab.psd1** is the *only* file that names a hypervisor/provider. Topology
  and component recipes are hypervisor-agnostic.
- **topology** recipes are reusable across labs (e.g. `single-domain`,
  `two-forest-trust`).
- **component** recipes describe one host class (role, OS SKU, base DSC).
- **app** recipes are PowerShell modules exporting `Install-WorkLabAppRecipe`;
  they orchestrate framework primitives that wrap upstream DSC resources.

Identity is derived, never authored: a component declares `Role = 'dc'`; the
framework computes `lab-<slug>-dc01` / `<SLUG>-DC01`.

See [RECIPES.md](RECIPES.md) for the discovery seam and a worked example, and
[PROVIDERS.md](PROVIDERS.md) for the provider contract.

## Image cache & lab orchestration

**Hybrid template cache.** `Build-WorkLabImage` (Windows-only DISM pipeline)
produces a patched bootable ISO + manifest under `<cache>/images/<name>/`.
`Initialize-Lab` lazily materializes a provider *template* from that image:
if a sysprepped template already exists it is reused; otherwise an
**ephemeral per-image SDN VNet** is stood up, an install VM boots and
syspreps (autounattend ends in `sysprep /generalize /oobe /shutdown`), the VM
is `Export`ed to a template, and the ephemeral VNet is torn down. Clones are
re-NIC'd onto the real per-lab VNet (the template's build-VNet ref is stale).

**Orchestration flow** (`Initialize-Lab`):

```
lab.psd1 ──▶ topology ──▶ components (Role + Image)
   │
   ├─ ensure per-lab network            (provider New-Network)
   ├─ per image: ensure template        (lazy hybrid cache, above)
   ├─ per computer: clone + start       (provider Copy-Vm, re-NIC to lab VNet)
   └─ DSC promotion ······· deferred to Phase 2.5 (logged, not attempted)
```

Core never touches a hypervisor directly — every step dispatches through the
provider seam. `Remove-Lab`/`Get-Lab`/`Get-LabComputer` compose the same
seam. DISM/oscdimg live behind mockable private wrappers; the real pipeline
is gated (Windows + Proxmox + Windows ISO).

## Phased build plan

Phase 0 (done): skeleton, build/CI, core REAL pieces (discovery seam, provider
registry, secrets, slug collision, logging, classes), lifecycle stubs, provider
contract stubbed everywhere, Proxmox network ops + health REAL, one gated
Proxmox integration test.

Phases 1–8: Proxmox VM/ISO/template/snapshot → image pipeline + first lab →
VyOS → WSUS → multi-DC/forest topologies → app primitives → Hyper-V → VMware.
See [README.md](../README.md) for the full table.
