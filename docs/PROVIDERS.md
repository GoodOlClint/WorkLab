# WorkLab Provider Contract

A provider is a module named `WorkLab.<Name>` that implements an identical
cmdlet contract. Core never contains hypervisor-specific code; it dispatches
to the registered provider via dynamic command resolution.

## Dispatch mechanism

Core resolves and invokes provider cmdlets by module-qualified name. Every
provider exports identically-named contract cmdlets, so when more than one
provider module is loaded the shared names are shadowed in the global command
table and `Get-Command -Module` returns nothing for the shadowed module.
Resolution therefore goes through the module object, which is per-module and
immune to load order:

```powershell
$module = Get-Module -Name "WorkLab.$ProviderName"   # imported on demand
$cmd    = $module.ExportedCommands["$Verb-WorkLabProvider$Noun"]
& $cmd @Arguments
```

This is centralized in the private helper `Invoke-WorkLabProviderCommand`.
A provider is bound to a logical name with `Register-WorkLabProvider`:

```powershell
Register-WorkLabProvider -Name Proxmox -Options @{
    Server = 'pve.lab.local'
    Zone   = 'labzone'
    ApiToken = 'svc@pve!worklab=<uuid>'   # or Credential = <pscredential>
}
```

`Options` carries **non-secret** connection settings only. Secrets are routed
through SecretManagement (`New-WorkLabSecret` / `Get-WorkLabSecret`).

## The contract

Every provider exports these cmdlets. Each takes `[object] $Context` (a
`LabContext` or a hashtable property bag carrying `Options` and identity such
as `Slug`) plus provider-specific options. `$Context` is typed `[object]` so
provider modules stay decoupled from the core `WorkLab` classes.

### Connectivity & capabilities
- `Test-WorkLabProviderConnection` — health check; returns capability flags.
  Users do not call this directly; the core `Test-WorkLabProvider -Name <p>`
  cmdlet dispatches to it. It is nouned (like every other contract cmdlet) so
  it never collides with the core entrypoint when both modules are imported.

### Network ops
- `New-WorkLabProviderNetwork` — create the per-lab network.
- `Remove-WorkLabProviderNetwork`
- `Get-WorkLabProviderNetwork`

### Image / template ops
- `New-WorkLabProviderIso` / `Get-WorkLabProviderIso` / `Remove-WorkLabProviderIso`
- `Export-WorkLabProviderTemplate` / `Get-WorkLabProviderTemplate` / `Remove-WorkLabProviderTemplate`

### VM lifecycle
- `New-WorkLabProviderVm` (from ISO) / `Copy-WorkLabProviderVm` (from template)
- `Get-WorkLabProviderVm` / `Start-WorkLabProviderVm` / `Stop-WorkLabProviderVm` / `Remove-WorkLabProviderVm`

### Snapshot ops
- `Checkpoint-WorkLabProviderVm` / `Restore-WorkLabProviderVm`
- `Get-WorkLabProviderCheckpoint` / `Remove-WorkLabProviderCheckpoint`

## Status by provider (through Phase 1)

| Cmdlet group | Proxmox | Hyper-V | VMware |
|---|---|---|---|
| `Test-WorkLabProviderConnection` | **REAL** | stub (Phase 7) | stub (Phase 8) |
| Network ops | **REAL** | stub (Phase 7) | stub (Phase 8) |
| ISO / Template / VM / Snapshot | **REAL** | stub (Phase 7) | stub (Phase 8) |

The Proxmox provider is fully implemented (all 20 contract cmdlets, REAL +
idempotent) as of Phase 1. Hyper-V (Phase 7) and VMware (Phase 8) remain
stubs.

### Proxmox provider Options reference

Supplied via `Register-WorkLabProvider -Name Proxmox -Options @{ ... }`.
Op-specific options are validated at point of use, so a caller only needs the
options its operation touches.

| Option | Required for | Default |
|---|---|---|
| `Server` | everything (connect) | — |
| `ApiToken` *or* `Credential` | everything (connect) | — |
| `Port` | optional | 8006 |
| `SkipCertificateCheck` | optional | false |
| `Node` | VM / ISO / template / snapshot | — |
| `DiskStorage` | VM create | — |
| `IsoStorage` | ISO ops; ISO attach on VM create | — |
| `Zone` | network ops (pre-created SDN VLAN zone) | — |
| `VlanPoolStart` / `VlanPoolEnd` | network (VLAN tag pool) | 100 / 200 |
| `VmIdPoolStart` / `VmIdPoolEnd` | VM (VMID pool) | 9000 / 9999 |

Identity is derived, never authored: the VM name is `lab-<slug>-<role>NN`
and the Proxmox VMID is a stable hash of that name folded into the VMID pool
(mirrors the VLAN-tag scheme). A VMID/name collision fails fast.

Stubs throw `[System.NotImplementedException]` with a message naming the
provider and the phase the implementation is scheduled for.

## Behavioral expectations

1. **Idempotent Set ops.** `New-WorkLabProvider*` reconciles; an existing
   resource is returned unchanged, never duplicated. `Remove-` on a missing
   resource is a no-op. (Proxmox network ops already follow this.)
2. **Fast-fail with teaching errors.** Missing required option → throw with the
   exact `Register-WorkLabProvider` example to fix it.
3. **No ambient state reliance.** Acquire a session/handle inside the cmdlet
   and pass it explicitly to downstream SDK calls.
4. **Comment-based help** on every public cmdlet (synopsis, description,
   example, parameters).
5. **Clones get re-NIC'd to the lab network.** A template captured via the
   ephemeral image-build network carries a stale bridge reference;
   `Copy-WorkLabProviderVm` re-attaches `net0` to the per-lab VNet when
   `Context.Slug` is present (no-op without a Slug).

## Writing a new provider

1. Create `source/WorkLab.<Name>/` with `WorkLab.<Name>.psd1` +
   `WorkLab.<Name>.psm1` (the psm1 dot-sources `Private/` then `Public/` and
   `Export-ModuleMember`s the public set).
2. Add one `Public/<Verb>-WorkLabProvider<Noun>.ps1` per contract cmdlet.
   Start every cmdlet as a stub throwing `NotImplementedException`.
3. Put SDK glue in `Private/` (connection, identity derivation, normalization).
   Keep the public cmdlets thin.
4. Add the module to `build.yaml` `Modules:` and its name pattern is
   auto-resolved by `Register-WorkLabProvider -Name <Name>` (defaults to
   `WorkLab.<Name>`).
5. Add unit tests asserting every contract cmdlet exists with a `-Context`
   parameter and that stubs throw `NotImplementedException`.
6. Implement cmdlets in the provider's scheduled phase, preserving idempotency.

The Proxmox provider's network ops + `Test-WorkLabProviderConnection` are the
reference REAL implementation (see `source/WorkLab.Proxmox/`).
