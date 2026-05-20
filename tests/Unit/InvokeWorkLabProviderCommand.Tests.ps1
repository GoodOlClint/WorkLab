BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
    # ProviderRegistration is a class loaded by the module via dot-source at
    # import time; pull it into this test scope so we can build instances.
    . (Join-Path $PSScriptRoot '../../source/WorkLab/Classes/ProviderRegistration.ps1')
}

Describe 'Invoke-WorkLabProviderCommand dispatch seam' {
    BeforeEach {
        InModuleScope WorkLab {
            # Stand up a fake provider module on the fly so the seam can resolve
            # a real ExportedCommands entry without needing a real provider.
            $name = 'WorkLab.UnitFake'
            if (Get-Module $name) { Remove-Module $name -Force }
            $script:fakeMod = New-Module -Name $name -ScriptBlock {
                function Test-WorkLabProviderConnection {
                    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
                    param(
                        [Parameter(Mandatory)][object]$Context,
                        [Parameter(ValueFromRemainingArguments)]$Rest
                    )
                    # If ShouldProcess prompts (because Confirm wasn't suppressed),
                    # this throws on a non-interactive host. The seam's job is to
                    # force Confirm=$false; if it doesn't, this test catches it.
                    if ($PSCmdlet.ShouldProcess('fake', 'Test-WorkLabProviderConnection')) {
                        [pscustomobject]@{
                            ContextSlug   = $Context.Slug
                            WhatIfSeen    = $WhatIfPreference
                            ConfirmSeen   = $ConfirmPreference
                            DidShouldProc = $true
                        }
                    }
                }
                Export-ModuleMember -Function Test-WorkLabProviderConnection
            } -PassThru | Import-Module -PassThru -Force

            $script:fakeReg = [ProviderRegistration]::new('UnitFake', $name, @{})
        }
    }

    AfterEach {
        InModuleScope WorkLab {
            if ($script:fakeMod) { Remove-Module $script:fakeMod -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'dispatches Verb-WorkLabProvider<Noun> to the module ExportedCommands by name' {
        InModuleScope WorkLab {
            $r = Invoke-WorkLabProviderCommand -Provider $script:fakeReg `
                -Verb 'Test' -Noun 'Connection' `
                -Arguments @{ Context = [pscustomobject]@{ Slug = 'demo' } }
            $r.ContextSlug   | Should -Be 'demo'
            $r.DidShouldProc | Should -BeTrue
        }
    }

    It 'forces -Confirm:$false and -WhatIf:$false on the inner provider call' {
        # If the seam did NOT strip Confirm, the inner cmdlet (ConfirmImpact='High')
        # would re-prompt and ShouldProcess on a non-interactive host throws
        # NullReferenceException. We assert by observing the preferences the
        # inner cmdlet sees inside its scope.
        InModuleScope WorkLab {
            $r = Invoke-WorkLabProviderCommand -Provider $script:fakeReg `
                -Verb 'Test' -Noun 'Connection' `
                -Arguments @{ Context = [pscustomobject]@{ Slug = 'x' } }
            $r.WhatIfSeen  | Should -Be $false
            $r.ConfirmSeen | Should -BeIn @('None', [System.Management.Automation.ConfirmImpact]::None)
        }
    }

    It 'does not mutate the caller-supplied Arguments hashtable' {
        InModuleScope WorkLab {
            $argsTable = @{ Context = [pscustomobject]@{ Slug = 'a' } }
            $copy = @{} + $argsTable
            $null = Invoke-WorkLabProviderCommand -Provider $script:fakeReg -Verb 'Test' -Noun 'Connection' -Arguments $argsTable
            # Caller's hashtable should still have just 'Context' (no Confirm/WhatIf seeped in).
            (Compare-Object ($argsTable.Keys | Sort-Object) ($copy.Keys | Sort-Object)) | Should -BeNullOrEmpty
        }
    }

    It 'throws when the provider does not export the contract cmdlet' {
        # Two terminal paths land us here:
        #   (a) module is on disk but doesn't export the verb-noun -> the seam's
        #       "does not satisfy the WorkLab contract" teaching error.
        #   (b) module isn't on disk (the in-memory fake here) -> Import-Module's
        #       "no valid module file was found" during the seam's self-heal.
        # Both are acceptable failure modes; the contract is "fail loudly", not
        # the exact wording.
        InModuleScope WorkLab {
            { Invoke-WorkLabProviderCommand -Provider $script:fakeReg -Verb 'Bogus' -Noun 'Verb' -Arguments @{ Context = 1 } } |
                Should -Throw
        }
    }
}
