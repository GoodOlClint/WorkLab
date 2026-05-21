<#
.SYNOPSIS
    Bootstrap a blank Windows 11 VM into a WorkLab verification host.

.DESCRIPTION
    Idempotent. Run as Administrator in either Windows PowerShell 5.1 (in-box)
    or PowerShell 7. Each step inspects current state and skips if already
    satisfied.

    What it installs / configures:
      1. PowerShell 7.6 (MSI via winget --installer-type wix). 7.7+ has no
         MSI; this script pins to a 7.6.x version on purpose.
      2. Git for Windows (machine scope).
      3. OpenSSH Server (Windows capability) + service Automatic + firewall
         rule + DefaultShell = pwsh.
      4. (Optional) SSH public key install for the local administrator who
         will SSH in (handles the elevated administrators_authorized_keys ACL
         requirement).
      5. Windows ADK Deployment Tools (DISM + oscdimg) via the ADK bootstrapper.
      6. Persistent User-scope env vars for the WorkLab gated integration
         tests (WORKLAB_VIRTIO_ISO, WORKLAB_IMG_TEST_SOURCE_ISO,
         WORKLAB_PROXMOX_TEST_*). Accepts a config PSD1 so the Proxmox token
         doesn't end up in PowerShell history.

    What it does NOT do (intentionally):
      - Clone the WorkLab repo. The repo is private; auth is your business.
      - Install PowerShell modules (PSFramework / Pester 5 / PSProxmoxVE).
        `build.ps1 -ResolveDependency` bootstraps them into
        `output/RequiredModules/`.
      - Set up Infisical / any SecretManagement vault. The gated image build
        uses a local `-AdminCredential`.

.PARAMETER ConfigFile
    Path to a PSD1 file containing the env-var hashtable and (optionally) an
    SSHPublicKey + SSHKeyUser. See `tools/win-vm-setup.example.psd1`.

.PARAMETER PowerShellVersion
    PowerShell 7 version prefix to install via winget. Default '7.6' - the
    script resolves the latest available version under that prefix (e.g.
    7.6.2) rather than pinning an exact build, because winget often doesn't
    carry the .0 of a series. Stays on 7.6.x on purpose: 7.7+ drops the
    machine-scope MSI (wix) installer.
    Do not bump past 7.6.x without a working machine-scope MSI install path.

.PARAMETER SkipPwsh / SkipGit / SkipSsh / SkipAdk / SkipEnv
    Skip individual phases (useful for re-runs / debugging).

.EXAMPLE
    # First-time bootstrap with a config file
    .\tools\win-vm-setup.ps1 -ConfigFile .\worklab-vm.psd1

.EXAMPLE
    # Re-run just to refresh env vars after editing the config
    .\tools\win-vm-setup.ps1 -ConfigFile .\worklab-vm.psd1 `
        -SkipPwsh -SkipGit -SkipSsh -SkipAdk

.NOTES
    Compatible with Windows PowerShell 5.1 (so it can run before pwsh 7 is
    installed). Avoid PS7-only syntax.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigFile,

    [string]$PowerShellVersion = '7.6',

    [switch]$SkipPwsh,
    [switch]$SkipGit,
    [switch]$SkipSsh,
    [switch]$SkipAdk,
    [switch]$SkipEnv
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colored console output is the primary UX of this setup script.')]
    param([string]$Message, [ValidateSet('Info','OK','Skip','Action','Warn','Fail')][string]$Kind = 'Info')
    $color = switch ($Kind) {
        'OK'     { 'Green' }
        'Skip'   { 'DarkGray' }
        'Action' { 'Cyan' }
        'Warn'   { 'Yellow' }
        'Fail'   { 'Red' }
        default  { 'White' }
    }
    $tag = switch ($Kind) {
        'OK'     { '[ok]    ' }
        'Skip'   { '[skip]  ' }
        'Action' { '[doing] ' }
        'Warn'   { '[warn]  ' }
        'Fail'   { '[fail]  ' }
        default  { '[info]  ' }
    }
    Write-Host ($tag + $Message) -ForegroundColor $color
}

function Assert-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "win-vm-setup.ps1 must run elevated (Administrator). Re-launch with 'Run as administrator'."
    }
}

function Assert-Windows11 {
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -notmatch 'Windows 1[01]') {
        Write-Step ("This script targets Windows 11. Detected: '{0}'. Proceeding, but YMMV." -f $os.Caption) 'Warn'
    }
}

function Assert-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required. Install 'App Installer' from Microsoft Store, then re-run."
    }
}

function Get-WingetPackageVersion {
    param([string]$Id)
    try {
        $out = winget list --id $Id --exact --accept-source-agreements 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $line = $out | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1
        if (-not $line) { return $null }
        # "Name  Id  Version  ..." -> take the third whitespace-separated field
        ($line -split '\s+') | Where-Object { $_ -match '^\d' } | Select-Object -First 1
    } catch { $null }
}

function Resolve-WorkLabPwshVersion {
    # Find the latest winget version of Microsoft.PowerShell under a prefix
    # (e.g. '7.6' -> '7.6.2'). winget frequently doesn't carry the '.0' of a
    # series, so pinning an exact build fails; resolve dynamically instead.
    param([Parameter(Mandatory)][string]$Prefix)
    $out = winget show --id Microsoft.PowerShell --versions --source winget --accept-source-agreements 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    $candidates = $out |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match "^$([regex]::Escape($Prefix))(\.|$)" } |
        Where-Object { $_ -match '^\d+(\.\d+)+$' }
    if (-not $candidates) { return $null }
    ($candidates | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
}

function Install-WorkLabPowerShell7 {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Version)

    # PowerShell 7 installs side-by-side; check the Program Files path.
    $pwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (Test-Path $pwshExe) {
        $existing = (& $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') 2>$null
        if ($existing -match "^$([regex]::Escape($Version))\.") {
            Write-Step ("PowerShell 7 already installed at $pwshExe (v$existing).") 'Skip'
            return
        }
        Write-Step ("PowerShell 7 found at $pwshExe but version is '$existing' (want $Version.x). Reinstalling.") 'Warn'
    }

    if (-not $PSCmdlet.ShouldProcess("PowerShell $Version.x MSI", 'winget install')) { return }

    # Resolve the exact latest build under the prefix (e.g. 7.6 -> 7.6.2).
    $resolved = Resolve-WorkLabPwshVersion -Prefix $Version
    if (-not $resolved) {
        throw "Could not find a winget version of Microsoft.PowerShell under '$Version'. Check 'winget show --id Microsoft.PowerShell --versions --source winget'."
    }

    Write-Step ("Installing PowerShell $resolved via winget (--installer-type wix; MSIX would be user-scope).") 'Action'
    $wingetArgs = @(
        'install', '--id', 'Microsoft.PowerShell',
        '--version', $resolved,
        '--source', 'winget',
        '--installer-type', 'wix',
        '--scope', 'machine',
        '--silent',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    & winget @wingetArgs
    if ($LASTEXITCODE -ne 0) { throw "winget install Microsoft.PowerShell $resolved failed (exit $LASTEXITCODE)." }

    if (-not (Test-Path $pwshExe)) {
        throw "winget reported success but $pwshExe is missing. Did winget pick a per-user MSIX after all? Try installing manually from the GitHub release MSI."
    }
    Write-Step ("PowerShell $resolved installed at $pwshExe.") 'OK'
}

function Install-WorkLabGit {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $v = (& git --version) -replace '^git version ',''
        Write-Step ("Git already on PATH (v$v).") 'Skip'
        return
    }
    if (-not $PSCmdlet.ShouldProcess('Git for Windows', 'winget install')) { return }

    Write-Step 'Installing Git for Windows (machine scope).' 'Action'
    & winget install --id Git.Git --exact --source winget --scope machine --silent `
        --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install Git.Git failed (exit $LASTEXITCODE)." }

    # Refresh PATH for the current session so a follow-on git call works.
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = ($machinePath, $userPath -join ';')

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Step 'Git installed but not on PATH in the current session. Open a new shell to use it.' 'Warn'
    } else {
        Write-Step ("Git installed: " + ((& git --version) -replace '^git version ','')) 'OK'
    }
}

function Install-WorkLabOpenSsh {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$SSHPublicKey,
        [string]$SSHKeyUser
    )

    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($cap.State -ne 'Installed') {
        if ($PSCmdlet.ShouldProcess('OpenSSH.Server', 'Add-WindowsCapability')) {
            Write-Step 'Installing Windows capability OpenSSH.Server.' 'Action'
            Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
        }
    } else {
        Write-Step 'OpenSSH.Server capability already installed.' 'Skip'
    }

    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'sshd service not present after capability install.' }
    if ($svc.StartType -ne 'Automatic') {
        if ($PSCmdlet.ShouldProcess('sshd', 'Set-Service -StartupType Automatic')) {
            Write-Step 'Setting sshd to start automatically.' 'Action'
            Set-Service -Name sshd -StartupType Automatic
        }
    } else {
        Write-Step 'sshd startup already Automatic.' 'Skip'
    }
    if ($svc.Status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess('sshd', 'Start-Service')) {
            Start-Service sshd
            Write-Step 'sshd started.' 'OK'
        }
    } else {
        Write-Step 'sshd already running.' 'Skip'
    }

    # A fresh VM's NIC lands on the Public profile (Windows categorizes
    # unidentified networks as Public). Move non-domain connection profiles to
    # Private - the right category for a trusted lab network. Best-effort: the
    # SSH rule below is set to all profiles regardless, so connectivity does
    # not depend on this succeeding.
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction Stop |
            Where-Object { $_.NetworkCategory -eq 'Public' }
        foreach ($p in $profiles) {
            if ($PSCmdlet.ShouldProcess("interface $($p.InterfaceAlias)", 'Set-NetConnectionProfile -NetworkCategory Private')) {
                Set-NetConnectionProfile -InterfaceIndex $p.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                Write-Step "Set network profile to Private on '$($p.InterfaceAlias)'." 'OK'
            }
        }
        if (-not $profiles) { Write-Step 'No Public network profiles to reclassify.' 'Skip' }
    }
    catch {
        Write-Step "Could not reclassify network profile (continuing; SSH rule covers all profiles): $($_.Exception.Message)" 'Warn'
    }

    # Firewall: the OpenSSH capability install creates 'OpenSSH-Server-In-TCP'
    # scoped to the Private profile ONLY. A fresh VM's NIC is almost always on
    # the Public profile (Windows categorizes unidentified networks as Public),
    # so that rule doesn't apply and TCP 22 is silently filtered ("Operation
    # timed out", not "refused"). Force the rule to all profiles so SSH works
    # regardless of how Windows categorized the network.
    $rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($rule) {
        if ($PSCmdlet.ShouldProcess('OpenSSH-Server-In-TCP', 'Set-NetFirewallRule -Profile Any -Enabled True')) {
            Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any -Enabled True | Out-Null
            Write-Step 'OpenSSH-Server-In-TCP firewall rule set to all profiles + enabled.' 'OK'
        }
    } else {
        if ($PSCmdlet.ShouldProcess('OpenSSH-Server-In-TCP', 'New-NetFirewallRule')) {
            Write-Step 'Creating firewall rule OpenSSH-Server-In-TCP (TCP 22 inbound, all profiles).' 'Action'
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
                -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Enabled True -Profile Any | Out-Null
        }
    }

    # Allow inbound ICMPv4 echo so the host is pingable (Windows blocks it by
    # default). Not required for SSH, but the WorkLab tooling uses ping for
    # liveness/health checks, and it makes the VM far easier to diagnose.
    $icmpRule = 'WorkLab-ICMPv4-Echo-In'
    if (-not (Get-NetFirewallRule -Name $icmpRule -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($icmpRule, 'New-NetFirewallRule (ICMPv4 echo)')) {
            New-NetFirewallRule -Name $icmpRule -DisplayName 'WorkLab ICMPv4 Echo Request' `
                -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Enabled True -Profile Any | Out-Null
            Write-Step 'Enabled inbound ICMPv4 echo (ping).' 'OK'
        }
    } else {
        Write-Step 'ICMPv4 echo rule already present.' 'Skip'
    }

    # Default shell + powershell subsystem = pwsh 7. Use the 8.3 short name
    # because Win32-OpenSSH has a long-standing bug (PowerShell/Win32-OpenSSH
    # #784) where Subsystem entries with spaces in the path silently fail
    # with `__NamedPipeError__` and `Invoke-Command -HostName` returns
    # "The SSH transport process has abruptly terminated". The DefaultShell
    # value is read by some shells fine with spaces, but using the short
    # name there too keeps the two consistent.
    $pwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (Test-Path $pwshExe) {
        $pwshShort = Get-WorkLabShortPath -Path $pwshExe
        Set-WorkLabOpenSshDefaultShell -PwshShortPath $pwshShort
        $sshdRestartNeeded = Set-WorkLabOpenSshPwshSubsystem -PwshShortPath $pwshShort
    } else {
        Write-Step 'PowerShell 7 missing; leaving OpenSSH DefaultShell + Subsystem at their defaults.' 'Warn'
        $sshdRestartNeeded = $false
    }

    # Optional SSH public key install.
    if ($SSHPublicKey) {
        if (-not $SSHKeyUser) { throw 'SSHPublicKey provided without SSHKeyUser; specify which local account the key belongs to.' }
        Install-WorkLabSshKey -PublicKey $SSHPublicKey -User $SSHKeyUser
    }

    if ($sshdRestartNeeded) {
        if ($PSCmdlet.ShouldProcess('sshd', 'Restart-Service (to pick up Subsystem change)')) {
            Write-Step 'Restarting sshd to activate updated Subsystem line.' 'Action'
            Restart-Service sshd
            Write-Step 'sshd restarted.' 'OK'
        }
    }
}

function Get-WorkLabShortPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Get-WorkLabShortPath: '$Path' not found." }
    # Windows-only: GetShortPathName via Scripting.FileSystemObject (no Add-Type needed).
    $fso = New-Object -ComObject Scripting.FileSystemObject
    try {
        $file = $fso.GetFile($Path)
        return $file.ShortPath
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($fso)
    }
}

function Set-WorkLabOpenSshDefaultShell {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$PwshShortPath)
    $key = 'HKLM:\SOFTWARE\OpenSSH'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $current = (Get-ItemProperty -Path $key -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    if ($current -eq $PwshShortPath) {
        Write-Step ("OpenSSH DefaultShell already set to $PwshShortPath.") 'Skip'
        return
    }
    if ($PSCmdlet.ShouldProcess('HKLM:\SOFTWARE\OpenSSH DefaultShell', "Set to $PwshShortPath")) {
        New-ItemProperty -Path $key -Name DefaultShell -Value $PwshShortPath -PropertyType String -Force | Out-Null
        Write-Step ("Set OpenSSH DefaultShell to $PwshShortPath (8.3 form, no spaces).") 'OK'
    }
}

function Set-WorkLabOpenSshPwshSubsystem {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$PwshShortPath)
    # Returns $true if sshd_config was modified (caller should restart sshd).
    $cfg = "$env:ProgramData\ssh\sshd_config"
    if (-not (Test-Path $cfg)) {
        Write-Step "sshd_config missing at $cfg; can't configure powershell subsystem." 'Warn'
        return $false
    }
    $desired = ('Subsystem powershell {0} -sshs -NoLogo -NoProfile' -f $PwshShortPath)
    $lines = Get-Content -Path $cfg
    $existingIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#?\s*Subsystem\s+powershell\b') { $existingIdx = $i; break }
    }
    if ($existingIdx -ge 0 -and $lines[$existingIdx].Trim() -ceq $desired) {
        Write-Step 'sshd_config Subsystem powershell already matches (8.3 path, sshs).' 'Skip'
        return $false
    }
    if (-not $PSCmdlet.ShouldProcess($cfg, "Set Subsystem powershell = $desired")) { return $false }
    if ($existingIdx -ge 0) {
        $lines[$existingIdx] = $desired
        Write-Step ('Replaced sshd_config Subsystem powershell line ({0}).' -f ($existingIdx + 1)) 'OK'
    } else {
        $lines = @($lines) + @('', '# Added by win-vm-setup.ps1', $desired)
        Write-Step 'Appended Subsystem powershell to sshd_config.' 'OK'
    }
    # Back up once, then write atomically.
    $bak = "$cfg.wlbak"
    if (-not (Test-Path $bak)) { Copy-Item $cfg $bak -Force }
    Set-Content -Path $cfg -Value $lines -Encoding ASCII
    return $true
}

function Install-WorkLabSshKey {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$PublicKey, [string]$User)

    $user = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
    if (-not $user) { throw "Local user '$User' does not exist. Create the account first or pass an existing user via -SSHKeyUser." }
    if (-not $user.Enabled) {
        Write-Step ("Local user '$User' exists but is DISABLED. The key will be installed but the account can never authenticate via SSH. (Built-in Administrator is disabled by default on Win11; specify a different SSHKeyUser if that's the issue.)") 'Warn'
    }

    $isAdmin = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "\\$User$" })

    if ($isAdmin) {
        # Elevated users are served by C:\ProgramData\ssh\administrators_authorized_keys with restricted ACLs.
        $keyFile = "$env:ProgramData\ssh\administrators_authorized_keys"
        $existing = if (Test-Path $keyFile) { Get-Content $keyFile -Raw } else { '' }
        if ($existing -notmatch [regex]::Escape($PublicKey.Trim())) {
            if ($PSCmdlet.ShouldProcess($keyFile, "Append public key for elevated user '$User'")) {
                Add-Content -Path $keyFile -Value $PublicKey.Trim()
                # Restricted ACL: Administrators + SYSTEM only, no inheritance.
                & icacls $keyFile /inheritance:r 2>&1 | Out-Null
                & icacls $keyFile /grant 'Administrators:F' 'SYSTEM:F' 2>&1 | Out-Null
                Write-Step ("Installed SSH public key for elevated user '$User' into $keyFile and locked ACL.") 'OK'
            }
        } else {
            Write-Step ("SSH public key for elevated user '$User' already present in $keyFile.") 'Skip'
        }
    } else {
        # Non-admin: ~\.ssh\authorized_keys
        $profilePath = "C:\Users\$User"
        if (-not (Test-Path $profilePath)) {
            throw "Profile $profilePath does not exist; have $User log in once to create it, then re-run."
        }
        $sshDir = Join-Path $profilePath '.ssh'
        $keyFile = Join-Path $sshDir 'authorized_keys'
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
        $existing = if (Test-Path $keyFile) { Get-Content $keyFile -Raw } else { '' }
        if ($existing -notmatch [regex]::Escape($PublicKey.Trim())) {
            if ($PSCmdlet.ShouldProcess($keyFile, "Append public key for '$User'")) {
                Add-Content -Path $keyFile -Value $PublicKey.Trim()
                & icacls $keyFile /inheritance:r 2>&1 | Out-Null
                & icacls $keyFile /grant "${User}:F" 'SYSTEM:F' 'Administrators:F' 2>&1 | Out-Null
                Write-Step ("Installed SSH public key for '$User' into $keyFile.") 'OK'
            }
        } else {
            Write-Step ("SSH public key for '$User' already present.") 'Skip'
        }
    }
}

function Install-WorkLabWindowsAdk {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    # Detect oscdimg, which lives at:
    # %ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { $pf86 = 'C:\Program Files (x86)' }
    $oscdimg = Join-Path $pf86 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    if (Test-Path $oscdimg) {
        Write-Step ("Windows ADK Deployment Tools already present ($oscdimg).") 'Skip'
        return
    }

    if (-not $PSCmdlet.ShouldProcess('Windows ADK (DeploymentTools feature)', 'download + install')) { return }

    # winget's Microsoft.WindowsADK package installs the bootstrapper but does
    # NOT select features by default. Use the bootstrapper directly so we can
    # select only DeploymentTools (~150 MB) instead of the whole ADK.
    $url = 'https://go.microsoft.com/fwlink/?linkid=2289980'   # ADK 10.1.26100.1 (Win11 24H2) bootstrapper
    $tmp = Join-Path $env:TEMP "adksetup-$([guid]::NewGuid().ToString('N')).exe"
    Write-Step ("Downloading ADK bootstrapper to $tmp.") 'Action'
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

    Write-Step 'Running ADK bootstrapper: DeploymentTools feature only (DISM + oscdimg).' 'Action'
    $p = Start-Process -FilePath $tmp -ArgumentList '/quiet','/norestart','/features','OptionId.DeploymentTools' -PassThru -Wait
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "ADK bootstrapper exited $($p.ExitCode)." }

    if (-not (Test-Path $oscdimg)) { throw "ADK install reported success but oscdimg missing at $oscdimg." }
    Write-Step ("ADK Deployment Tools installed; oscdimg at $oscdimg.") 'OK'
}

function Set-WorkLabUserEnv {
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$EnvVars)
    if (-not $EnvVars -or $EnvVars.Count -eq 0) {
        Write-Step 'No EnvVars in config; skipping User env-var sync.' 'Skip'
        return
    }
    foreach ($name in ($EnvVars.Keys | Sort-Object)) {
        $want = [string]$EnvVars[$name]
        $have = [Environment]::GetEnvironmentVariable($name, 'User')
        # Redact values for anything that looks like a secret so the script's
        # output (which may end up in CI logs, screen recordings, or a chat
        # transcript) does not leak the value.
        $isSecret = $name -match '(?i)(TOKEN|SECRET|PASSWORD|PWD|APIKEY|API_KEY|CREDENTIAL)'
        $shown = if ($isSecret) { "<redacted, len=$($want.Length)>" } else { "'$want'" }
        if ($have -eq $want) {
            Write-Step ("env:$name already set to expected value (User scope).") 'Skip'
            continue
        }
        if ($PSCmdlet.ShouldProcess("env:$name (User scope)", "Set to $shown")) {
            [Environment]::SetEnvironmentVariable($name, $want, 'User')
            Write-Step ("Set User env:$name = $shown") 'OK'
        }
    }
}

# ---- main ----------------------------------------------------------

Assert-Elevated
Assert-Windows11
Assert-Winget

$config = @{ EnvVars = @{} }
if ($ConfigFile) {
    if (-not (Test-Path $ConfigFile)) { throw "ConfigFile not found: $ConfigFile" }
    $loaded = Import-PowerShellDataFile -Path $ConfigFile
    foreach ($k in $loaded.Keys) { $config[$k] = $loaded[$k] }
    Write-Step ("Loaded config from $ConfigFile.") 'Info'
}

if (-not $SkipPwsh) { Install-WorkLabPowerShell7 -Version $PowerShellVersion } else { Write-Step 'Skipping PowerShell 7 phase (-SkipPwsh).' 'Skip' }
if (-not $SkipGit)  { Install-WorkLabGit }                                       else { Write-Step 'Skipping Git phase (-SkipGit).' 'Skip' }
if (-not $SkipSsh)  { Install-WorkLabOpenSsh -SSHPublicKey $config.SSHPublicKey -SSHKeyUser $config.SSHKeyUser } else { Write-Step 'Skipping OpenSSH phase (-SkipSsh).' 'Skip' }
if (-not $SkipAdk)  { Install-WorkLabWindowsAdk }                                else { Write-Step 'Skipping ADK phase (-SkipAdk).' 'Skip' }
if (-not $SkipEnv)  { Set-WorkLabUserEnv -EnvVars $config.EnvVars }              else { Write-Step 'Skipping env-vars phase (-SkipEnv).' 'Skip' }

Write-Step 'Done. To pick up the new PATH (git, pwsh), open a new shell.' 'OK'
Write-Step 'Next: clone the WorkLab repo manually (auth is your business), then run pwsh build.ps1 -ResolveDependency.' 'Info'
