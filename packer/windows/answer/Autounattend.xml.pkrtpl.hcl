<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
<!--
  Windows Server 2022 unattended installation answer file.

  Delivered as a CD (cd_files/cd_label) rather than a floppy. Most Packer Windows
  examples use floppy_files, which works but attaches a virtual floppy drive that
  then has to be removed before publishing, and floppy emulation is exactly the
  kind of legacy virtual hardware a modern image should not carry. A CD-ROM is
  ejected at the end of the install and leaves nothing behind.

  Setup searches removable media for Autounattend.xml automatically, so no boot
  command is needed at all -- which removes the single most fragile part of an
  ISO-based Packer build. Contrast Rocky (isolinux keystrokes) and Ubuntu (GRUB
  command line), both of which had to be settled by screenshotting the console.

  The image is Windows Server 2022 Standard Evaluation, Server Core.
  Server Core, not Desktop Experience, deliberately:
    - roughly a third of the disk footprint and a fraction of the patch surface
    - no GUI to harden, and no GUI-only tooling to become a dependency
    - it is what a golden image for automated infrastructure should be
  Desktop Experience is a one-line change to the /IMAGE/NAME value below.
-->

  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-GB</UILanguage>
      </SetupUILanguage>
      <InputLocale>0809:00000809</InputLocale>
      <SystemLocale>en-GB</SystemLocale>
      <UILanguage>en-GB</UILanguage>
      <UserLocale>en-GB</UserLocale>
    </component>

    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">

      <DiskConfiguration>
        <!--
          WillShowUI never: the whole point is that nobody is watching.
          A single partition, unlike the Linux images.

          That difference is deliberate and is explained in IMAGE-STANDARD.md.
          The Linux layout exists so that nodev/nosuid/noexec can be applied per
          filesystem and so a log flood cannot fill the root filesystem. Windows
          has neither mechanism -- mount options are not a Windows concept, and
          log growth is bounded by the event log's own size limits, which the
          hardening role sets. Splitting a Windows system disk to mirror Linux
          would be cargo-culting a control that does not exist on the platform.
        -->
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <!-- System Reserved, required for BIOS/MBR boot -->
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>Primary</Type>
              <Size>500</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Label>System Reserved</Label>
              <Format>NTFS</Format>
              <Active>true</Active>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
              <Label>Windows</Label>
              <Letter>C</Letter>
              <Format>NTFS</Format>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/NAME</Key>
              <!-- Server Core. "...SERVERSTANDARD" without the suffix is Desktop Experience. -->
              <Value>${windows_image_name}</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>

      <UserData>
        <!--
          No ProductKey element. The evaluation media is licensed for 180 days
          without one, and the licensing swap for real deployment is documented
          in docs/RUNBOOK.md. An image built from evaluation media must never be
          presented as production-ready, which is why the expiry is recorded in
          the image metadata as well as the docs.
        -->
        <AcceptEula>true</AcceptEula>
        <FullName>golden-image-factory</FullName>
        <Organization>golden-image-factory</Organization>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <ComputerName>${computer_name}</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>

    <component name="Microsoft-Windows-TerminalServices-LocalSessionManager"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <!-- RDP is enabled here and hardened (NLA) by the Ansible role. -->
      <fDenyTSConnections>false</fDenyTSConnections>
    </component>

    <component name="Microsoft-Windows-TerminalServices-RDP-WinStationExtensions"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <UserAuthentication>1</UserAuthentication>
      <SecurityLayer>2</SecurityLayer>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">

      <!--
        ELEMENT ORDER IS LOAD-BEARING HERE, and it is the trap that cost several
        build attempts.

        Windows unattend files are schema-validated, and the children of
        Microsoft-Windows-Shell-Setup must appear in the order the XSD defines:
        AutoLogon, then FirstLogonCommands, then OOBE, then UserAccounts.

        Setup does not report a schema violation. It silently IGNORES the whole
        answer file and falls back to an interactive install -- which presents as
        the language-selection screen sitting there until the WinRM timeout,
        with a valid, well-formed, correctly-delivered answer file that Setup
        simply never used. Well-formed XML is not the same as schema-valid XML,
        and only the second one counts here.

        Diagnosed by opening a WinPE command prompt over VNC (Shift+F10) and
        confirming A: existed and contained Autounattend.xml -- which ruled out
        delivery and left rejection as the only explanation.
      -->

      <AutoLogon>
        <Password>
          <Value>${winrm_password}</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>${admin_username}</Username>
      </AutoLogon>

      <FirstLogonCommands>
        <!--
          The only job here is to get WinRM up so Packer can connect; everything
          else is the Ansible role's. Ordering matters: the network profile must
          be Private before WinRM's firewall rules will apply, because the
          quickconfig refuses to open a public-profile port.
        -->
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>1</Order>
          <Description>Set network profile to Private</Description>
          <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>2</Order>
          <Description>Configure WinRM for Packer</Description>
          <!--
            The provisioning CD's drive letter is not fixed, so the script is
            located by searching rather than hardcoded.
          -->
          <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-ChildItem -Path D:\,E:\,F:\,G:\ -Filter enable-winrm.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($s) { &amp; $s.FullName } else { exit 1 }"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <UserAccounts>
        <AdministratorPassword>
          <!--
            Substituted by Packer at build time from PKR_VAR_winrm_password and
            never committed. Windows has no key-based equivalent to the ephemeral
            SSH key the Linux images use (ADR-0012), so a password is
            unavoidable -- the mitigation is that it is generated per build, lives
            only in the environment, and the account is disabled by sysprep
            before the image is published. See ADR-0018.

            Rendered by templatefile() into floppy_content, exactly as the Linux
            kickstart and autoinstall files are -- Packer does NOT template the
            contents of floppy_files, so a placeholder there would reach Setup
            verbatim and the install would fail with an unusable password.
          -->
          <Value>${winrm_password}</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

    </component>
  </settings>
</unattend>
