# Changelog

All notable changes to WorkLab are documented here. Format loosely follows
Keep a Changelog; the project is pre-1.0 and versioned by build phase.

## [0.4.0] - Phase 2.5

### Added
- **Provider contract: guest channel (4 new cmdlets, 20 → 24).**
  `Test-WorkLabProviderGuestAgent`, `Invoke-WorkLabProviderGuestCommand`,
  `Write-WorkLabProviderGuestFile`, `Read-WorkLabProviderGuestFile`. Every
  provider implements these against its native in-guest mechanism — no
  separate management network required, lab VNets stay isolatable.
- **Proxmox provider: 4 new cmdlets REAL via qemu-guest-agent**
  (`Test-PveVmGuestAgent` / `Invoke-PveVmGuestExec` / `Write-PveVmGuestFile`
  / `Read-PveVmGuestFile`). `Test-WorkLabProviderGuestAgent` returns
  `Reachable=$false` rather than throwing when the agent is down.
- **`Build-WorkLabImage -VirtioWinIso`**: injects the virtio storage/NIC
  drivers offline into `install.wim`, stages `qemu-ga.msi` at
  `C:\Windows\Setup\Files\qemu-ga.msi`, and prepends a FirstLogonCommand to
  `msiexec /i ... /qn /norestart` **before** the sysprep command. Without
  this the guest agent cannot exist on the first boot of a cloned VM (you
  cannot install the agent through the agent). Manifest gains `virtioWinIso`,
  `virtioSha256`, `guestAgentPath`; idempotency signature includes
  `virtioSha256`.
- **Core guest-channel primitives** (private dispatch wrappers):
  `Wait-WorkLabProviderGuestAgentReady` (poll until reachable; throws on
  timeout, default 600s/5s), `Invoke-WorkLabGuestCommand`,
  `Push-WorkLabGuestFile`, `Get-WorkLabGuestFile`. All route through
  `Invoke-WorkLabProviderCommand` so swapping providers does not touch core.
- **`Invoke-WorkLabDscResource`**: push a small in-guest script via the guest
  channel, transport the property hashtable as base64-encoded JSON (PS 5.1
  in-guest has no `-AsHashtable`), run Test → Set if needed → Test, return
  JSON. Targets `powershell.exe` (WinPS 5.1, always present); built-in
  resources (File/Script) work without shipping any DSC modules, so the
  primitive is exercised end-to-end without role-specific DSC.
- **`Initialize-Lab` waits for the guest agent** post-clone (per computer);
  result gains `GuestAgentReachable`. Timeout is a Warning, not a throw —
  the rest of the lab can usually proceed and the caller can re-probe.
- Gated `Phase2_5_GuestAgent` integration test: build image with
  `-VirtioWinIso` → `Initialize-Lab helloworld` on real Proxmox → assert
  reachable → `Invoke-WorkLabDscResource` against the built-in File
  resource → read the file back via `Read-WorkLabProviderGuestFile` →
  `Remove-Lab` cleanup. Skips unless `WORKLAB_VIRTIO_ISO` + Proxmox env set.

### Changed
- `Initialize-Lab` no longer warns "ADDS/role DSC deferred"; it logs a
  Significant info line when the agent is reachable. `DscDeferred=$true`
  remains on the lab summary and now means "no role-specific DSC recipes
  have been applied" (the *channel* is fully real).

### Decisions recorded
- **Guest reachability = native in-guest agent per provider.** Closes the
  Phase 2 open question (DSC-over-PSRemoting on isolated VNets). Proxmox =
  qemu-ga; Hyper-V (Phase 7) = PowerShell Direct + `Copy-Item -VMSession`;
  VMware (Phase 8) = vSphere guest operations.
- **Role-specific DSC (ADDS, SQL, etc.) deferred to recipe-validation
  rounds.** Phase 2.5 ships the *channel* + `Invoke-WorkLabDscResource`
  primitive. ActiveDirectoryDsc/SqlServerDsc/etc. ship with the recipes that
  need them, not pre-built into the framework. Scope discipline.

## [0.3.1] - Phase 2 verification fix

### Fixed
- `Expand-WorkLabIsoSource` now clears the read-only attribute across the
  extracted tree, and `Mount-WorkLabWim` defensively clears it on the WIM
  before mount. Without this, `Mount-WindowsImage` failed with
  "You do not have permissions to mount and modify this image..." because
  files copied from a mounted ISO inherit the source's read-only flag.
  Surfaced by the first real end-to-end run of `Build-WorkLabImage` on a
  Windows host (Win11 + ADK + WS2025 ISO) — exactly the scenario the
  Phase 2 mocked unit tests could not cover. End-to-end now completes in
  ~3 min and produces an idempotent, manifest-sha-checked patched ISO.

## [0.3.0] - Phase 2

### Added
- **`Build-WorkLabImage`** (REAL, Windows-gated, idempotent): copies the
  source ISO, mounts the selected `install.wim` edition, injects optional
  drivers/updates, writes an autounattend (local-admin from
  `-AdminCredential` or `worklab/image/local-admin/<name>`; ends in
  sysprep `/generalize /oobe /shutdown`), rebuilds a bootable ISO into the
  cache, records a manifest. DISM/oscdimg are isolated behind mockable seams;
  fast-fails on non-Windows by design.
- **`Get-WorkLabImage` / `Remove-WorkLabImage`** REAL (cross-platform image
  cache: `<cache>/images/<name>/`).
- **Lazy hybrid template cache** (`New-WorkLabImageTemplate`): reuse an
  existing sysprepped template, else stand up an **ephemeral per-image SDN
  VNet**, boot+sysprep an install VM, `Export` it to a template, and tear the
  ephemeral VNet down (always, via `finally`).
- **REAL `Initialize-Lab` / `Remove-Lab` / `Get-Lab` / `Get-LabComputer`**:
  orchestrate the discovery seam + Phase 1 provider ops to stand up / tear
  down / inspect the single-DC `helloworld` lab. Idempotent.
- `Copy-WorkLabProviderVm` now re-attaches the clone's NIC to the per-lab
  VNet when `Context.Slug` is present (templates carry a stale ephemeral
  build-VNet reference).
- `dc.component.psd1` gains `Image = 'ws2025-core'`.
- Gated `ImagePipeline` integration test (Windows + Proxmox + Windows ISO;
  self-skips).

### Deferred
- **ADDS DSC promotion → Phase 2.5.** `Initialize-Lab` logs the deferred DSC
  step; guest reachability on the isolated per-lab VNet is an open decision.

### Notes
- The DISM/boot/sysprep path is Windows-only and was **not executable on the
  macOS dev box**; it is covered by mocked unit tests + the gated
  integration test (reported UNVERIFIED-on-this-box by design).

## [0.2.0] - Phase 1

### Added
- **Proxmox provider fully implemented** (all 20 contract cmdlets REAL +
  idempotent) via PSProxmoxVE:
  - ISO ops: `New-WorkLabProviderIso` (URL via Invoke-PveStorageDownload or
    local upload via Send-PveFile), `Get-`, `Remove-`.
  - VM lifecycle: `New-` (NIC on the per-lab SDN VNet, optional ISO/boot),
    `Get-` (single + slug-prefix list mode), `Start-`, `Stop-`, `Remove-`,
    `Copy-` (full clone from template).
  - Template: `Export-WorkLabProviderTemplate` (convert-VM-to-template
    primitive; sysprep/DISM capture is Phase 2), `Get-`, `Remove-`.
  - Snapshots: `Checkpoint-`, `Restore-`, `Get-WorkLabProviderCheckpoint`,
    `Remove-WorkLabProviderCheckpoint`.
  - `Test-WorkLabProviderConnection` capability flags now all REAL.
- Deterministic VMID derivation: VM name hashed into a configurable VMID pool
  (`VmIdPoolStart`/`End`, default 9000-9999) with VMID/name collision
  fast-fail; backs the now-functional `Test-WorkLabSlugCollision` provider
  path.
- Proxmox private foundation: context normalization (op-specific options
  validated at point of use, not globally), `Assert-WorkLabProxmoxOption`,
  VM-identity/VM-target/template/snapshot resolvers, task waiter.
- Lightweight gated Proxmox VM-lifecycle integration test.

### Changed
- `Resolve-WorkLabProxmoxContext` no longer hard-requires `Zone`; network
  cmdlets assert it explicitly (behavior preserved, message improved).

## [0.1.0] - Phase 0

### Added
- Sampler-flavored multi-module monorepo skeleton (`build.ps1`, `build.yaml`,
  `RequiredModules.psd1`, `.build/` Invoke-Build tasks).
- CI: GitHub Actions + Azure Pipelines (parallel build+test, gated integration).
- `WorkLab` core:
  - Classes: `LabContext`, `ProviderRegistration`, `RecipeReference`.
  - REAL recipe discovery seam: `Resolve-WorkLabRecipePath`,
    `Get-WorkLabRecipe`, `Import-WorkLabRecipe` (in-tree / side-loaded /
    module sources, precedence, namespace qualification).
  - REAL provider registry: `Register-WorkLabProvider`, `Get-WorkLabProvider`,
    `Test-WorkLabProvider` (dynamic module-qualified dispatch).
  - REAL secret routing: `New-/Get-/Remove-WorkLabSecret` (vault-agnostic
    SecretManagement wrapper, `worklab/<slug>/<role>/<name>` namespace).
  - REAL `Test-WorkLabSlugCollision` (slug validation + name derivation).
  - PSFramework structured logging.
  - Lifecycle/snapshot/image cmdlets as stubs that build a `LabContext` and
    warn that orchestration is a later phase.
- `WorkLab.Proxmox` / `WorkLab.HyperV` / `WorkLab.VMware`: full provider
  contract (20 cmdlets each). All stubbed (`NotImplementedException`) except
  Proxmox `Test-WorkLabProviderConnection` and
  `New-/Remove-/Get-WorkLabProviderNetwork` (REAL, idempotent SDN VNet ops via
  PSProxmoxVE). Core `Test-WorkLabProvider -Name` dispatches to the provider's
  nouned `Test-WorkLabProviderConnection` (avoids a name collision with the
  core entrypoint).
- `WorkLabDsc` empty module skeleton.
- Sample recipes (`helloworld` lab, `single-domain` topology, `dc` component,
  `DomainController` app) and docs (ARCHITECTURE, PROVIDERS, RECIPES,
  DECISIONS, README, CONTRIBUTING).
- Pester 5 unit tests (classes, discovery seam, provider registry, secrets,
  slug collision, provider stub contract) and one gated Proxmox integration
  test (network create/get/destroy).
