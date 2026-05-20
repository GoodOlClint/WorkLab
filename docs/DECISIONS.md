# Decisions & Anti-Patterns

This file records what we deliberately **do not** do, and why. Prior
iterations of this project sprawled because new functionality landed in the
"least bad" location instead of its correct one. If code does not fit cleanly
into the module structure, **stop and reconsider the structure** — do not
wedge it in.

## Anti-patterns (do not do these)

### Do not embed hypervisor-specific code in core `WorkLab`
Hypervisor knowledge lives in `WorkLab.<Provider>` modules only. Core
dispatches through `Invoke-WorkLabProviderCommand`. If you are importing a
hypervisor SDK in `source/WorkLab/`, you are in the wrong module.

### Do not skip the discovery seam by hardcoding recipe paths
All recipe resolution goes through `Resolve-WorkLabRecipePath` /
`Get-WorkLabRecipe` / `Import-WorkLabRecipe`. No `Join-Path $here 'recipes'`
shortcuts. The seam's three sources (in-tree, side-loaded, module) are the
contract.

### Do not write to disk outside the sanctioned roots
Only `$env:LOCALAPPDATA\WorkLab\` (logs, state — resolved by
`Get-WorkLabStateRoot`) or `$env:WORKLAB_CACHE_PATH` (default `~/.worklab/cache`
for templates and patched ISOs — resolved by `Get-WorkLabCacheRoot`). Nothing
writes into the repo, the module install path, or arbitrary temp.

### Do not implement MOF compilation or a pull server
DSC is applied via `Invoke-DscResource` in method-call mode over PSRemoting.
No `Start-DscConfiguration`, no `.mof`, no LCM pull configuration, ever.

### Do not let recipe files reference hypervisor-specific configuration
Topology and component recipes are hypervisor-agnostic. Provider mapping
(name + options) appears **only** in the `lab.psd1` `Provider` block.

### Do not put hypervisor identifiers (VMIDs, etc.) in recipes
Proxmox is VMID-keyed; WorkLab identity is name-based. The provider derives
the VMID as a stable hash of the WorkLab VM name into a configurable VMID
pool (`Options.VmIdPool{Start,End}`), exactly as the per-lab VLAN tag is
derived from the slug. Recipes never carry VMIDs or any hypervisor numbering;
a VMID/name collision fails fast (widen the pool or change the slug).

### Do not select or require a specific SecretManagement vault
WorkLab is vault-agnostic. It calls `Get-Secret`/`Set-Secret`/`Remove-Secret`
and routes to whatever vault the user registered as default. It never calls
`Register-SecretVault` or `Set-SecretVaultDefault`. If no vault is registered,
fail fast with a message pointing the user to `Register-SecretVault`. Vault
selection and registration are the user's responsibility, out of band.

### Do not introduce module-scoped mutable state
The only module-scoped mutable state is the provider registration table
(`$script:WorkLabProviders`, managed via `Register-WorkLabProvider` /
`Get-WorkLabProvider`). Everything else flows through `LabContext` as a
parameter. No module-scoped "current lab", caches, or counters.

### Do not return generic errors
Every fast-fail throw names the problem and the fix (the exact cmdlet/field to
correct). Errors teach.

## Implementation notes that look like deviations but are intentional

- **Sampler-flavored, not stock Sampler.** Stock Sampler builds one module per
  repo; this is a multi-module monorepo. `build.ps1`/`build.yaml`/
  `RequiredModules.psd1` follow Sampler conventions, but the build is driven by
  Invoke-Build task files under `.build/` that iterate every module in
  `source/`. See [CONTRIBUTING.md](../CONTRIBUTING.md).
- **Classes are dot-sourced, tested by dot-source.** `using module` does not
  see runtime-dot-sourced classes. Phase 0 unit tests dot-source the class
  files directly (in dependency order) and exercise cmdlets via
  `Import-Module` + property assertions. A ModuleBuilder merge that makes
  `using module` work is deferred until it is actually needed.
- **`$Context` is `[object]` in provider cmdlets.** Deliberate: provider
  modules must not take a hard dependency on core's `LabContext` class. They
  read `Options`/`Slug` as a property bag.

- **`Build-WorkLabImage` is Windows-only and fast-fails elsewhere.** DISM
  image servicing + ADK oscdimg are Windows-only. `Assert-WorkLabDismAvailable`
  throws a teaching error on non-Windows. The pipeline's DISM/oscdimg/ISO
  steps are isolated behind private seam wrappers so the orchestration logic
  is unit-tested cross-platform with the seams mocked; the real pipeline is a
  gated integration test (Windows + Proxmox + Windows ISO).

- **Image-build VM uses an ephemeral per-image SDN VNet, not a lab VNet.**
  The install VM is not lab-scoped. The build stands up a throwaway VNet
  under a deterministic build slug and tears it down after templating
  (always, via `finally`). Because the resulting template's NIC then
  references a deleted bridge, `Copy-WorkLabProviderVm` re-attaches each
  clone's `net0` to the real per-lab VNet when `Context.Slug` is present.

- **ADDS DSC promotion deferred to Phase 2.5 (open question recorded).** The
  brief sets DSC = `Invoke-DscResource` over PSRemoting, but does not specify
  how the control host reaches a guest whose only NIC is on the isolated
  per-lab SDN VNet. `Initialize-Lab` logs the deferred DSC step and does not
  attempt it. The reachability model (management route vs. qemu-guest-agent
  exec) must be decided before Phase 2.5.
