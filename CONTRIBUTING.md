# Contributing to WorkLab

## The one rule

If you find yourself writing code that does not fit cleanly into the module
structure, **stop and reconsider the structure** — do not put it in the "least
bad" place. Prior iterations sprawled exactly this way. New functionality goes
in its correct module/folder or the structure changes deliberately; it does
not get wedged in. See [docs/DECISIONS.md](docs/DECISIONS.md).

## Module conventions

- One monorepo, modules under `source/`: `WorkLab` (core, **zero hypervisor
  code**), `WorkLab.<Provider>`, `WorkLabDsc`.
- Each module's `.psm1` dot-sources `Classes/` (core only, dependency order),
  then `Private/`, then `Public/`, and `Export-ModuleMember`s the public set.
- One public function per file; filename = function name.
- Comment-based help on every public cmdlet: synopsis, description, ≥1 example,
  every parameter documented.
- Fast-fail with teaching errors (name the fix). No silent failures.
- `Set` operations are idempotent (reconcile, never duplicate).
- Structured logging via `Write-PSFMessage` — never `Write-Verbose`/`Write-Host`.
- No module-scoped mutable state except the provider registration table.
- Provider cmdlets type `$Context` as `[object]` (no dependency on core
  classes).

## Build

Sampler-flavored but **not** stock Sampler: stock Sampler is single-module;
this monorepo iterates modules. `build.ps1` is the bootstrap (resolves deps
into `output/RequiredModules`, then Invoke-Build). Tasks live in
`.build/WorkLab.build.ps1`:

| Task | Does |
|---|---|
| `build` | assemble each `source/<Module>` into `output/module/<Module>/<version>` |
| `analyze` | PSScriptAnalyzer over `source/` (`.build/ScriptAnalyzerSettings.psd1`) |
| `unit` | Pester 5 over `tests/Unit` |
| `integration` | Pester 5 over `tests/Integration` (self-skips without env vars) |
| `test` | `analyze` + `unit` |
| `.` | `build` + `test` |

Add a new module to `build.yaml` `Modules:` to include it in the build.

## Tests

- Pester 5. Every REAL public cmdlet has ≥1 unit test.
- Test classes by dot-sourcing the class files in dependency order
  (`using module` does not see runtime-dot-sourced classes). Test cmdlets via
  `Import-Module` + property assertions; mock external modules
  (SecretManagement, PSProxmoxVE) at the WorkLab module scope.
- Integration tests are gated by environment variables and must self-skip when
  unset, so CI stays green without infrastructure:
  - Proxmox network: `WORKLAB_PROXMOX_TEST_HOST`, `WORKLAB_PROXMOX_TEST_TOKEN`,
    `WORKLAB_PROXMOX_TEST_NODE` (zone via `WORKLAB_PROXMOX_TEST_ZONE`).

## CI

- GitHub Actions (`.github/workflows/ci.yml`) and Azure Pipelines
  (`azure-pipelines.yml`) run `./build.ps1 -Tasks build, test` on Ubuntu +
  Windows in parallel, with a separate gated integration job.
- Build-dependency cache keyed on `RequiredModules.psd1`.

## Scope discipline

Build only what the current phase calls for ([README.md](README.md) phase
table). Do not implement ahead of the plan. Stubs throw
`[System.NotImplementedException]` naming the provider and the phase.
