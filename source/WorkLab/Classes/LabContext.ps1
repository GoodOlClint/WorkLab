# LabContext — the single object that flows through every WorkLab cmdlet.
#
# There is no module-scoped mutable lab state: identity, recipe binding,
# provider binding, and secret namespace all travel together here. The only
# module-scoped state in the framework is the provider registration table.
class LabContext {
    [string]$Slug
    [RecipeReference]$Recipe
    [ProviderRegistration]$Provider
    [string]$SecretNamespace      # 'worklab/<slug>'
    [string]$LogChannel           # PSFramework tag for structured logging

    LabContext([string]$slug, [RecipeReference]$recipe, [ProviderRegistration]$provider) {
        [LabContext]::AssertValidSlug($slug)
        $this.Slug = $slug
        $this.Recipe = $recipe
        $this.Provider = $provider
        $this.SecretNamespace = "worklab/$slug"
        $this.LogChannel = 'WorkLab'
    }

    # Slugs: 3-12 chars, lowercase alphanumeric, no hyphens. Fail fast and
    # teach the caller exactly what is allowed.
    static [void] AssertValidSlug([string]$slug) {
        if ($slug -cnotmatch '^[a-z0-9]{3,12}$') {
            throw [System.ArgumentException]::new(
                "Invalid lab slug '$slug'. Slugs must be 3-12 characters, " +
                'lowercase alphanumeric, no hyphens (regex: ^[a-z0-9]{3,12}$). ' +
                "Fix the 'Slug' field in the .lab.psd1."
            )
        }
    }

    # Hypervisor-facing VM name: lab-<slug>-<role><nn>  e.g. lab-twoforest-dc01
    [string] VmName([string]$role, [int]$n) {
        return ('lab-{0}-{1}{2:D2}' -f $this.Slug, $role.ToLower(), $n)
    }

    # Windows computer name: <SLUG>-<ROLE><nn>  e.g. TWOFOREST-DC01
    # Enforces the 15-char NetBIOS limit.
    [string] ComputerName([string]$role, [int]$n) {
        $name = ('{0}-{1}{2:D2}' -f $this.Slug.ToUpper(), $role.ToUpper(), $n)
        if ($name.Length -gt 15) {
            throw [System.ArgumentException]::new(
                "Computed computer name '$name' is $($name.Length) chars, " +
                'over the 15-char NetBIOS limit. Use a shorter slug or role token.'
            )
        }
        return $name
    }

    [string] LocalAdminSecretPath([string]$computer) {
        return ('{0}/local-admin/{1}' -f $this.SecretNamespace, $computer)
    }

    [string] DomainAdminSecretPath([string]$domain) {
        return ('{0}/domain-admin/{1}' -f $this.SecretNamespace, $domain)
    }

    [string] ServiceAccountSecretPath([string]$name) {
        return ('{0}/svc/{1}' -f $this.SecretNamespace, $name)
    }

    [string] ToString() {
        $prov = if ($this.Provider) { $this.Provider.Name } else { '<none>' }
        return ('LabContext(slug={0}, provider={1})' -f $this.Slug, $prov)
    }
}
