BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Test-WorkLabSlugCollision (explicit set)' {
    It 'reports no collision and the derived candidate names' {
        $r = Test-WorkLabSlugCollision -Slug twoforest -Role dc, mem -ExistingVmName 'lab-other-dc01' -NoThrow
        $r.HasCollision | Should -BeFalse
        $r.CandidateName | Should -Be @('lab-twoforest-dc01', 'lab-twoforest-mem01')
    }
    It 'fast-fails on collision by default' {
        { Test-WorkLabSlugCollision -Slug twoforest -Role dc -ExistingVmName 'lab-twoforest-dc01' } |
            Should -Throw -ExpectedMessage '*collides*'
    }
    It 'returns the collision instead of throwing with -NoThrow' {
        $r = Test-WorkLabSlugCollision -Slug twoforest -Role dc -ExistingVmName 'LAB-TWOFOREST-DC01' -NoThrow
        $r.HasCollision | Should -BeTrue          # case-insensitive match
        $r.Collision | Should -Be @('lab-twoforest-dc01')
    }
    It 'rejects an invalid slug' {
        { Test-WorkLabSlugCollision -Slug 'BAD' -Role dc -ExistingVmName @() } | Should -Throw
    }
}
