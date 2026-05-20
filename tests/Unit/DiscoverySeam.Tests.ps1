BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force

    $script:SideLoad = Join-Path ([System.IO.Path]::GetTempPath()) "wl-sl-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path (Join-Path $script:SideLoad 'labs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:SideLoad 'components') | Out-Null
    # A side-loaded clone of 'helloworld' with a different slug (precedence probe).
    Set-Content -Path (Join-Path $script:SideLoad 'labs/helloworld.lab.psd1') -Value "@{ Slug = 'sideload' }"
    Set-Content -Path (Join-Path $script:SideLoad 'components/extra.component.psd1') -Value "@{ Role = 'extra' }"
    $env:WORKLAB_RECIPE_PATH = $script:SideLoad
}

AfterAll {
    Remove-Item env:WORKLAB_RECIPE_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $script:SideLoad -ErrorAction SilentlyContinue
}

Describe 'Resolve-WorkLabRecipePath' {
    It 'returns the in-tree repo recipes root first' {
        $roots = @(Resolve-WorkLabRecipePath)
        $roots[0].Source | Should -Be 'InTree'
        $roots[0].Root | Should -Match 'recipes$'
        $roots[0].Exists | Should -BeTrue
    }
    It 'includes side-loaded paths from WORKLAB_RECIPE_PATH' {
        $sl = @(Resolve-WorkLabRecipePath) | Where-Object Source -EQ 'SideLoaded'
        $sl.Root | Should -Contain $script:SideLoad
    }
}

Describe 'Get-WorkLabRecipe' {
    It 'discovers in-tree recipes of every type' {
        (Get-WorkLabRecipe -Type lab).Name | Should -Contain 'helloworld'
        (Get-WorkLabRecipe -Type topology).Name | Should -Contain 'single-domain'
        (Get-WorkLabRecipe -Type component).Name | Should -Contain 'dc'
        (Get-WorkLabRecipe -Type app).Name | Should -Contain 'DomainController'
    }
    It 'discovers side-loaded recipes' {
        (Get-WorkLabRecipe -Type component).Name | Should -Contain 'extra'
    }
    It 'filters by name' {
        $r = @(Get-WorkLabRecipe -Name dc -Type component)
        $r | Should -HaveCount 1
        $r[0].Type | Should -Be 'component'
    }
}

Describe 'Import-WorkLabRecipe' {
    It 'loads a lab recipe as data, in-tree winning precedence' {
        $lab = Import-WorkLabRecipe -Name helloworld -Type lab
        $lab.IsApp | Should -BeFalse
        $lab.Data.Slug | Should -Be 'helloworld'   # in-tree, not the side-loaded 'sideload'
    }
    It 'loads an app recipe and validates the export' {
        $app = Import-WorkLabRecipe -Name DomainController -Type app
        $app.IsApp | Should -BeTrue
        $app.Install.Name | Should -Be 'Install-WorkLabAppRecipe'
        $app.Install.Parameters.Keys | Should -Contain 'ComputerName'
        $app.Install.Parameters.Keys | Should -Contain 'LabId'
    }
    It 'throws a teaching error for an unknown recipe' {
        { Import-WorkLabRecipe -Name does-not-exist -Type lab } | Should -Throw -ExpectedMessage '*Get-WorkLabRecipe*'
    }
}
