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
        [Parameter()][string]$VirtioDriverMsiPath,
        [Parameter()][ValidateSet('Uefi', 'Bios')][string]$Firmware = 'Uefi',
        [Parameter()][string]$ProductKey,
        [Parameter(Mandatory)][string]$OutFile
    )

    $plain = [pscredential]::new('x', $AdminPassword).GetNetworkCredential().Password
    # Windows obfuscates each unattend password as base64(UTF16LE(password +
    # <containing element name>). The suffix differs per field: the
    # AdministratorPassword element uses 'AdministratorPassword'; the AutoLogon
    # Password element uses 'Password'. Reusing one value for both makes
    # AutoLogon's password decode wrong -> AutoLogon silently fails -> the VM
    # sits at the logon screen and FirstLogonCommands (qemu-ga + sysprep)
    # never run.
    $encAdmin = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($plain + 'AdministratorPassword'))
    $encAutoLogon = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($plain + 'Password'))
    $imageKey = if ($Edition -match '^\d+$') {
        "<MetaData wcm:action=`"add`"><Key>/IMAGE/INDEX</Key><Value>$Edition</Value></MetaData>"
    }
    else {
        "<MetaData wcm:action=`"add`"><Key>/IMAGE/NAME</Key><Value>$Edition</Value></MetaData>"
    }

    # Product key (windowsPE UserData). Volume/eval media stop at an interactive
    # "enter product key" screen unless a key is supplied; a KMS client setup
    # key (Microsoft-published, edition-specific) lets Setup proceed unattended
    # without activating. Omitted when no key is given.
    $productKeyXml = if ($ProductKey) {
        "<ProductKey><Key>$ProductKey</Key><WillShowUI>OnError</WillShowUI></ProductKey>"
    }
    else { '' }

    # Build FirstLogonCommands: install the virtio guest-tools drivers, then the
    # guest agent (each when supplied), BEFORE sysprep so they land in the
    # DriverStore / service registry and survive generalize. The driver MSI runs
    # first so the virtio-serial driver (vioser) is present before qemu-ga's
    # service binds its channel. The non-storage virtio drivers (vioser, NetKVM,
    # balloon, ...) are installed here, online, by the vendor MSI rather than
    # offline-injected: the virtio-win ISO's per-driver/per-OS/per-arch layout
    # makes a single recursive DISM Add-WindowsDriver fail (mixed x86/ARM64), and
    # the MSI does the arch/OS matching for us. Storage drivers (viostor/vioscsi)
    # still MUST be offline-injected (see Build-WorkLabImage) -- the disk has to
    # be visible before Setup runs and at first boot, long before FirstLogon.
    # The commands run sequentially under AutoLogon=Administrator.
    # ADDLOCAL=ALL forces every driver feature to install locally. The
    # virtio-win-gt MSI's features are all install-level 1 (so /qn would install
    # them anyway), but the MSI ships no INSTALLLEVEL property, so be explicit
    # rather than rely on the engine's default level -- this is also the
    # documented unattended invocation.
    $cmds = [System.Collections.Generic.List[string]]::new()
    if ($VirtioDriverMsiPath) {
        $cmds.Add(('        <SynchronousCommand wcm:action="add"><Order>{0}</Order><CommandLine>msiexec /i "{1}" /qn /norestart ADDLOCAL=ALL</CommandLine><Description>WorkLab virtio guest-tools driver install (Phase 2.5)</Description></SynchronousCommand>' -f ($cmds.Count + 1), $VirtioDriverMsiPath))
    }
    if ($GuestAgentMsiPath) {
        $cmds.Add(('        <SynchronousCommand wcm:action="add"><Order>{0}</Order><CommandLine>msiexec /i "{1}" /qn /norestart</CommandLine><Description>WorkLab guest-agent install (Phase 2.5)</Description></SynchronousCommand>' -f ($cmds.Count + 1), $GuestAgentMsiPath))
    }
    $cmds.Add(('        <SynchronousCommand wcm:action="add"><Order>{0}</Order><CommandLine>%WINDIR%\System32\Sysprep\Sysprep.exe /generalize /oobe /shutdown /quiet</CommandLine><Description>WorkLab sysprep and shutdown (build-complete signal)</Description></SynchronousCommand>' -f ($cmds.Count + 1)))
    $firstLogon = $cmds -join "`n"

    # Disk layout must match the VM firmware. UEFI needs a GPT layout (EFI
    # System Partition + MSR + Windows); legacy BIOS needs a single active
    # primary (MBR). A mismatch leaves the installed disk non-bootable and the
    # VM PXE/CD-loops. WorkLab VMs are OVMF/UEFI by default (see
    # New-WorkLabProviderVm), so 'Uefi' is the default.
    if ($Firmware -eq 'Uefi') {
        $diskConfig = @'
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
'@
        $installTo = '<InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>'
    }
    else {
        $diskConfig = @'
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Active>true</Active><Format>NTFS</Format><Label>Windows</Label></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
'@
        $installTo = '<InstallTo><DiskID>0</DiskID><PartitionID>1</PartitionID></InstallTo>'
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$Locale</UILanguage></SetupUILanguage>
      <InputLocale>$Locale</InputLocale><SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage><UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
$diskConfig
      <ImageInstall>
        <OSImage>
          <InstallFrom>$imageKey</InstallFrom>
          $installTo
        </OSImage>
      </ImageInstall>
      <UserData>$productKeyXml<AcceptEula>true</AcceptEula></UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserAccounts>
        <AdministratorPassword><Value>$encAdmin</Value><PlainText>false</PlainText></AdministratorPassword>
      </UserAccounts>
      <OOBE><HideEULAPage>true</HideEULAPage><ProtectYourPC>3</ProtectYourPC><SkipMachineOOBE>true</SkipMachineOOBE><SkipUserOOBE>true</SkipUserOOBE></OOBE>
      <ComputerName>*</ComputerName>
      <AutoLogon><Password><Value>$encAutoLogon</Value><PlainText>false</PlainText></Password><Enabled>true</Enabled><Username>Administrator</Username><LogonCount>1</LogonCount></AutoLogon>
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
