function New-WorkLabAutounattend {
    <#
    .SYNOPSIS
        Render an autounattend.xml for an unattended Windows install.
    .DESCRIPTION
        Pure XML generation (cross-platform, unit-testable). Embeds the local
        administrator password per the Windows unattend spec: base64 of
        UTF-16LE(password + 'AdministratorPassword'), PlainText=false. The
        computer name is left to Windows ('*'); per-host specialization
        happens later (Phase 2.5+). Returns the written file path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Edition,
        [Parameter(Mandatory)][securestring]$AdminPassword,
        [Parameter()][string]$Locale = 'en-US',
        [Parameter()][string]$GuestAgentMsiPath,
        [Parameter(Mandatory)][string]$OutFile
    )

    $plain = [pscredential]::new('x', $AdminPassword).GetNetworkCredential().Password
    $enc = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($plain + 'AdministratorPassword'))
    $imageKey = if ($Edition -match '^\d+$') {
        "<MetaData wcm:action=`"add`"><Key>/IMAGE/INDEX</Key><Value>$Edition</Value></MetaData>"
    }
    else {
        "<MetaData wcm:action=`"add`"><Key>/IMAGE/NAME</Key><Value>$Edition</Value></MetaData>"
    }

    # Build FirstLogonCommands: install the guest agent (when supplied) BEFORE
    # sysprep so the agent service is registered and survives generalize. The
    # commands run sequentially under AutoLogon=Administrator.
    $cmds = [System.Collections.Generic.List[string]]::new()
    if ($GuestAgentMsiPath) {
        $cmds.Add(('        <SynchronousCommand wcm:action="add"><Order>{0}</Order><CommandLine>msiexec /i "{1}" /qn /norestart</CommandLine><Description>WorkLab guest-agent install (Phase 2.5)</Description></SynchronousCommand>' -f ($cmds.Count + 1), $GuestAgentMsiPath))
    }
    $cmds.Add(('        <SynchronousCommand wcm:action="add"><Order>{0}</Order><CommandLine>%WINDIR%\System32\Sysprep\Sysprep.exe /generalize /oobe /shutdown /quiet</CommandLine><Description>WorkLab sysprep and shutdown (build-complete signal)</Description></SynchronousCommand>' -f ($cmds.Count + 1)))
    $firstLogon = $cmds -join "`n"

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$Locale</UILanguage></SetupUILanguage>
      <InputLocale>$Locale</InputLocale><SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage><UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ImageInstall><OSImage><InstallFrom>$imageKey</InstallFrom></OSImage></ImageInstall>
      <UserData><AcceptEula>true</AcceptEula></UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserAccounts>
        <AdministratorPassword><Value>$enc</Value><PlainText>false</PlainText></AdministratorPassword>
      </UserAccounts>
      <OOBE><HideEULAPage>true</HideEULAPage><ProtectYourPC>3</ProtectYourPC><SkipMachineOOBE>true</SkipMachineOOBE><SkipUserOOBE>true</SkipUserOOBE></OOBE>
      <ComputerName>*</ComputerName>
      <AutoLogon><Password><Value>$enc</Value><PlainText>false</PlainText></Password><Enabled>true</Enabled><Username>Administrator</Username><LogonCount>1</LogonCount></AutoLogon>
      <FirstLogonCommands>
$firstLogon
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@

    if ($PSCmdlet.ShouldProcess($OutFile, 'Write autounattend.xml')) {
        $dir = Split-Path -Parent $OutFile
        if ($dir) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Set-Content -LiteralPath $OutFile -Value $xml -Encoding utf8
    }
    $OutFile
}
