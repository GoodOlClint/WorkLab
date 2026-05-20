# RecipeReference — a discovered recipe and where it came from.
# Source is one of: InTree | SideLoaded | Module
# Type   is one of: lab | topology | component | app
class RecipeReference {
    [string]$Name
    [string]$Type
    [string]$Path
    [string]$Source
    [string]$ModuleName    # set when Source -eq 'Module'
    [string]$Namespace     # set for collision-qualified references

    RecipeReference([string]$name, [string]$type, [string]$path, [string]$source) {
        $this.Name = $name
        $this.Type = $type
        $this.Path = $path
        $this.Source = $source
    }

    # Namespace-qualified name used to disambiguate collisions across sources,
    # e.g. 'Semperis.WorkLab.Recipes/dsp-install'.
    [string] QualifiedName() {
        if ([string]::IsNullOrWhiteSpace($this.Namespace)) {
            return $this.Name
        }
        return ('{0}/{1}' -f $this.Namespace, $this.Name)
    }

    [string] ToString() {
        return ('{0} [{1}] ({2})' -f $this.QualifiedName(), $this.Type, $this.Source)
    }
}
