BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
}

Describe 'Wait-WorkLabProviderGuestAgentReady' {
    It 'returns ready when the probe exec succeeds and stdout matches setup-complete' {
        InModuleScope WorkLab {
            $script:probe = $null
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                $script:probe = $Arguments
                [pscustomobject]@{ ExitCode = 0; Stdout = '    ImageState    REG_SZ    IMAGE_STATE_COMPLETE'; Stderr = '' }
            }
            (Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 5).Reachable |
                Should -BeTrue
            # Default probe is the Windows ImageState query, run as an exec.
            $script:probe.Command | Should -Be 'reg.exe'
            $script:probe.Arguments | Should -Contain 'ImageState'
        }
    }
    It 'keeps waiting (then times out) while setup is still in progress' {
        InModuleScope WorkLab {
            # Agent answers, but ImageState isn't COMPLETE yet -> not ready.
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                [pscustomobject]@{ ExitCode = 0; Stdout = '    ImageState    REG_SZ    IMAGE_STATE_UNDEPLOYABLE'; Stderr = '' }
            }
            { Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 0 } |
                Should -Throw -ExpectedMessage '*Timed out*'
        }
    }
    It 'treats an exec failure (agent not running / mid-reboot) as not-ready' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' { throw 'QEMU guest agent is not running' }
            { Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 0 } |
                Should -Throw -ExpectedMessage '*Timed out*'
        }
    }
    It 'honors a custom (non-Windows) readiness probe' {
        InModuleScope WorkLab {
            $script:probe = $null
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                $script:probe = $Arguments
                [pscustomobject]@{ ExitCode = 0; Stdout = 'running'; Stderr = '' }
            }
            (Wait-WorkLabProviderGuestAgentReady -Provider @{} -Context @{} -VmName lab-x-dc01 -TimeoutSeconds 5 `
                -ReadyCommand 'systemctl' -ReadyArguments @('is-system-running') -ReadySuccessPattern 'running').Ready |
                Should -BeTrue
            $script:probe.Command | Should -Be 'systemctl'
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

    It 'tolerates a UTF-8 BOM on the guest result file (PS 5.1 writes one)' {
        InModuleScope WorkLab {
            Mock Invoke-WorkLabProviderCommand -RemoveParameterType 'Provider' {
                switch ("$Verb-$Noun") {
                    'Write-GuestFile' { return [pscustomobject]@{ Path = $Arguments.Path; Bytes = 1 } }
                    'Invoke-GuestCommand' { return [pscustomobject]@{ ExitCode = 0; Stdout = ''; Stderr = ''; Pid = 1 } }
                    'Read-GuestFile' {
                        # Leading U+FEFF BOM, as Windows PowerShell 5.1 Set-Content -Encoding utf8 emits.
                        $json = (@{ InDesiredStateBefore = $false; SetApplied = $true; InDesiredStateAfter = $true; Error = $null } | ConvertTo-Json)
                        return [pscustomobject]@{ Content = ([char]0xFEFF + $json) }
                    }
                }
            }

            $r = Invoke-WorkLabDscResource -Provider @{} -Context @{} -VmName lab-x-dc01 `
                -ResourceName File -ModuleName PSDesiredStateConfiguration `
                -Property @{ DestinationPath = 'C:\hello.txt'; Contents = 'hi'; Ensure = 'Present' } -Confirm:$false

            # Parses despite the BOM (no ConvertFrom-Json failure).
            $r.InDesiredStateAfter | Should -BeTrue
            $r.SetApplied | Should -BeTrue
        }
    }
}
