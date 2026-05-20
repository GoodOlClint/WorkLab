BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Wait-WorkLabProviderGuestAgentReady' {
    It 'returns when the agent reports reachable' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                [pscustomobject]@{ Reachable = $true; VmName = 'lab-x-dc01' }
            }
            (Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 5).Reachable |
                Should -BeTrue
        }
    }
    It 'throws on timeout' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                [pscustomobject]@{ Reachable = $false }
            }
            { Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 0 } |
                Should -Throw -ExpectedMessage '*Timed out*'
        }
    }
}

Describe 'Invoke-WorkLabDscResource' {
    It 'pushes a script + executes + parses the JSON result' {
        InModuleScope WorkLab {
            $script:pushed = $null
            $script:executed = $null
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                switch ("$Verb-$Noun") {
                    'Write-GuestFile' {
                        $script:pushed = $Arguments
                        return [pscustomobject]@{ Provider = 'Proxmox'; Path = $Arguments.Path; Bytes = $Arguments.Content.Length }
                    }
                    'Invoke-GuestCommand' {
                        $script:executed = $Arguments
                        return [pscustomobject]@{ ExitCode = 0; Stdout = ''; Stderr = ''; Pid = 1 }
                    }
                    'Read-GuestFile' {
                        return [pscustomobject]@{
                            Content = (@{
                                InDesiredStateBefore = $false
                                SetApplied           = $true
                                InDesiredStateAfter  = $true
                                Error                = $null
                            } | ConvertTo-Json)
                        }
                    }
                }
            }

            $r = Invoke-WorkLabDscResource -Provider @{} -Context @{} -VmName lab-x-dc01 `
                -ResourceName File -ModuleName PSDesiredStateConfiguration `
                -Property @{ DestinationPath = 'C:\hello.txt'; Contents = 'hi'; Ensure = 'Present' } -Confirm:$false

            $r.ResourceName | Should -Be 'File'
            $r.InDesiredStateBefore | Should -BeFalse
            $r.SetApplied | Should -BeTrue
            $r.InDesiredStateAfter | Should -BeTrue
            $r.ExitCode | Should -Be 0

            # Pushed script targets a wl-dsc-*.ps1 temp path and embeds the
            # base64-encoded property JSON.
            $script:pushed.Path | Should -BeLike 'C:\Windows\Temp\wl-dsc-*.ps1'
            $expectedB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(
                    (@{ DestinationPath = 'C:\hello.txt'; Contents = 'hi'; Ensure = 'Present' } | ConvertTo-Json -Depth 6 -Compress)))
            $script:pushed.Content | Should -BeLike "*$expectedB64*"

            # Executed powershell.exe -File <scriptpath>
            $script:executed.Command | Should -Be 'powershell.exe'
            $script:executed.Arguments | Should -Contain '-File'
            $script:executed.Arguments | Should -Contain $script:pushed.Path
        }
    }
}
