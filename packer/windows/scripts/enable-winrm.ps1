# Bring WinRM up so Packer can connect. Run once, by FirstLogonCommands.
#
# This is the ONLY thing that happens outside Ansible on the Windows image. The
# hardening -- including tearing WinRM back down -- is the harden_windows role, so
# that the Windows and Linux images are configured by the same tool and reviewed
# the same way.
#
# WinRM is configured for HTTP with Basic auth and AllowUnencrypted here, which
# looks alarming written down and is worth being precise about:
#
#   - it exists only inside the build, on a VM reachable solely through the
#     hypervisor's port forward on 127.0.0.1
#   - the credential is generated per build and never leaves the build host
#   - harden_windows disables Basic, disables unencrypted transport, and removes
#     the firewall rule before sysprep, and the Pester suite asserts all three
#
# The alternative -- HTTPS with a self-signed certificate -- moves the trust
# problem rather than solving it, because Packer would then have to skip
# certificate validation anyway. What makes this safe is the teardown, not the
# transport, so the teardown is what is tested. See ADR-0017.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Start-Transcript -Path 'C:\Windows\Temp\enable-winrm.log' -Append | Out-Null

Write-Output 'Configuring WinRM for the build...'

# The service must be running before winrm can be configured at all.
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# quickconfig refuses to open a port on a Public network profile. The answer file
# sets the profile to Private first, but a race between DHCP and first logon can
# leave it Public, so it is enforced again here rather than assumed.
Get-NetConnectionProfile | ForEach-Object {
    if ($_.NetworkCategory -ne 'Private') {
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
    }
}

winrm quickconfig -quiet -force

winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'

# The default listener is created by quickconfig; this makes the intent explicit
# and is idempotent if it already exists.
if (-not (Get-ChildItem -Path WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTP' })) {
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
}

New-NetFirewallRule -DisplayName 'WinRM-HTTP-Build' `
    -Name 'WinRM-HTTP-Build' `
    -Direction Inbound `
    -LocalPort 5985 `
    -Protocol TCP `
    -Action Allow `
    -Profile Any `
    -ErrorAction SilentlyContinue | Out-Null

# Ansible's WinRM connection needs the shell to be reachable for a script, not
# just a command, and the default 150 MB memory limit is not enough for the
# Windows Update module.
Restart-Service -Name WinRM

Write-Output 'WinRM is configured. Listener:'
winrm enumerate winrm/config/listener

Stop-Transcript | Out-Null
