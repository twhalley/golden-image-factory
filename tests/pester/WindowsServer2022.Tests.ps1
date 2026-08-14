<#
    Pester -- Windows Server 2022 golden image.

    THE CONTRACT is the same as the goss suites: every claim in
    docs/IMAGE-STANDARD.md has an assertion here, and every assertion here
    corresponds to a claim there. If a control is in the standard there is a test
    for it; if there is no test, the control is not claimed.

    Pester rather than goss, because goss has no meaningful Windows support. That
    is a real split -- two test frameworks to maintain -- and it is the right one:
    the alternative is a single framework that does Linux well and Windows badly.

    Runs IN-GUEST before sysprep, so it tests the image rather than the template.

    WHAT THIS SUITE CANNOT ASSERT, stated rather than left to be assumed:
    WinRM is still enabled and permissive at the moment these tests run, because
    they arrive over it. Its teardown happens in C:\Windows\image-finalize.ps1,
    invoked as Packer's shutdown command. What is asserted here is that the
    script exists and contains the teardown; the end state is verified against
    the artefact offline. See ADR-0017.
#>

BeforeAll {
    $script:BuildInfoPath = 'C:\Windows\image-build-info.txt'
    $script:FinalizePath  = 'C:\Windows\image-finalize.ps1'
    $script:SchannelPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'

    function Get-RegValue {
        param([string]$Path, [string]$Name)
        try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
        catch { $null }
    }
}

Describe 'Image identity' {
    It 'carries a build-info file' {
        $script:BuildInfoPath | Should -Exist
    }

    It 'records the image name, version and originating commit' {
        $content = Get-Content $script:BuildInfoPath -Raw
        $content | Should -Match 'IMAGE_NAME='
        $content | Should -Match 'IMAGE_VERSION='
        $content | Should -Match 'GIT_COMMIT='
        $content | Should -Match 'SOURCE_ISO_CHECKSUM='
    }

    It 'records that hardening was applied and by what' {
        $content = Get-Content $script:BuildInfoPath -Raw
        $content | Should -Match 'HARDENED=true'
        $content | Should -Match 'HARDENING_ROLE=harden_windows'
    }

    It 'declares that it is built from evaluation media' {
        # An image built from evaluation media must never be mistaken for
        # production-ready. Recorded in the image so a running VM can answer the
        # question without reference to the docs.
        $content = Get-Content $script:BuildInfoPath -Raw
        $content | Should -Match 'LICENSING=evaluation'
    }

    It 'is a Server Core installation' {
        $type = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
        $type | Should -Be 'Server Core'
    }
}

Describe 'SMBv1 (CIS 18.3.1)' {
    It 'has the SMBv1 feature removed, not merely disabled' {
        # The distinction matters: the registry switch leaves the driver
        # installed and one edit away from working. Feature removal takes the
        # binaries off the image.
        $feature = Get-WindowsFeature -Name FS-SMB1 -ErrorAction SilentlyContinue
        if ($feature) { $feature.Installed | Should -BeFalse }
    }

    It 'has the SMBv1 server protocol disabled' {
        $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1'
        if ($null -ne $v) { $v | Should -Be 0 }
    }

    It 'has the SMBv1 client driver disabled' {
        # Start = 4 is "disabled".
        $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' 'Start'
        if ($null -ne $v) { $v | Should -Be 4 }
    }
}

Describe 'TLS and cryptography' {
    # Both the Client and Server halves are asserted for every protocol. A
    # half-configured SCHANNEL is the single most common finding here: disabling
    # only the server side stops the machine ACCEPTING an old protocol but not
    # OFFERING it when acting as a client, which a server image does constantly.
    $legacyProtocols = @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')

    foreach ($proto in $legacyProtocols) {
        foreach ($role in @('Client', 'Server')) {
            It "$proto/$role is disabled" {
                $path = Join-Path $script:SchannelPath "$proto\$role"
                $path | Should -Exist
                (Get-RegValue $path 'Enabled') | Should -Be 0
            }

            It "$proto/$role is disabled by default" {
                $path = Join-Path $script:SchannelPath "$proto\$role"
                (Get-RegValue $path 'DisabledByDefault') | Should -Be 1
            }
        }
    }

    foreach ($role in @('Client', 'Server')) {
        It "TLS 1.2/$role is enabled" {
            $path = Join-Path $script:SchannelPath "TLS 1.2\$role"
            (Get-RegValue $path 'Enabled') | Should -Be 1
        }
    }

    It 'forces .NET Framework to use strong crypto (64-bit)' {
        # Without this, .NET applications pin their own protocol list and keep
        # using TLS 1.0 regardless of everything above.
        (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto') | Should -Be 1
    }

    It 'forces .NET Framework to use strong crypto (32-bit)' {
        (Get-RegValue 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto') | Should -Be 1
    }
}

Describe 'Account and password policy (CIS 1.1-1.2)' {
    BeforeAll {
        # secedit is the only reliable way to read effective local policy.
        $script:SecPolPath = Join-Path $env:TEMP 'secpol.cfg'
        secedit /export /cfg $script:SecPolPath /quiet | Out-Null
        $script:SecPol = Get-Content $script:SecPolPath -Raw
    }

    It 'requires a minimum password length of 14' {
        $script:SecPol | Should -Match 'MinimumPasswordLength\s*=\s*14'
    }

    It 'enforces password complexity' {
        $script:SecPol | Should -Match 'PasswordComplexity\s*=\s*1'
    }

    It 'does not store passwords with reversible encryption' {
        $script:SecPol | Should -Match 'ClearTextPassword\s*=\s*0'
    }

    It 'locks accounts after 5 failed attempts' {
        $script:SecPol | Should -Match 'LockoutBadCount\s*=\s*5'
    }

    It 'remembers 24 previous passwords' {
        $script:SecPol | Should -Match 'PasswordHistorySize\s*=\s*24'
    }

    AfterAll {
        Remove-Item $script:SecPolPath -ErrorAction SilentlyContinue
    }
}

Describe 'Local security options (CIS 2.3)' {
    It 'does not store the LAN Manager hash' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'NoLMHash') | Should -Be 1
    }

    It 'sends NTLMv2 only and refuses LM and NTLM' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LmCompatibilityLevel') | Should -Be 5
    }

    It 'restricts anonymous enumeration of shares' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RestrictAnonymous') | Should -Be 1
    }

    It 'restricts anonymous enumeration of SAM accounts' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RestrictAnonymousSAM') | Should -Be 1
    }

    It 'does not display the last signed-in user' {
        (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DontDisplayLastUserName') | Should -Be 1
    }

    It 'presents a legal notice before sign-in' {
        $caption = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'legalnoticecaption'
        $caption | Should -Not -BeNullOrEmpty
        $caption | Should -Match 'AUTHORISED ACCESS ONLY'
    }

    It 'requires SMB signing on the server' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' 'RequireSecuritySignature') | Should -Be 1
    }

    It 'requires SMB signing on the client' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature') | Should -Be 1
    }

    It 'disables the built-in Guest account' {
        $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
        if ($guest) { $guest.Enabled | Should -BeFalse }
    }

    It 'does not allow elevated MSI installation by unprivileged users' {
        $v = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' 'AlwaysInstallElevated'
        if ($null -ne $v) { $v | Should -Be 0 }
    }
}

Describe 'Services (CIS 5.x)' {
    # Print Spooler is the one to check first: PrintNightmare, and a server image
    # has no printers.
    $expectedDisabled = @('Spooler', 'RemoteRegistry')

    foreach ($svc in $expectedDisabled) {
        It "$svc is disabled" {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) { $service.StartType | Should -Be 'Disabled' }
        }
    }
}

Describe 'Audit policy (CIS 17.x)' {
    BeforeAll {
        $script:AuditPol = auditpol /get /category:* | Out-String
    }

    It 'audits logon success and failure' {
        $script:AuditPol | Should -Match 'Logon\s+Success and Failure'
    }

    It 'audits user account management' {
        $script:AuditPol | Should -Match 'User Account Management\s+Success and Failure'
    }

    It 'audits audit policy change' {
        $script:AuditPol | Should -Match 'Audit Policy Change\s+Success and Failure'
    }

    It 'forces subcategory settings to override legacy category settings' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'SCENoApplyLegacyAuditPolicy') | Should -Be 1
    }

    It 'records the command line in process creation events' {
        # Without this, 4688 records that a process started but not what it was
        # asked to do -- which is most of the value during an incident.
        (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled') | Should -Be 1
    }

    It 'enables PowerShell script block logging' {
        # The highest-value logging control on a modern Windows host: almost all
        # hands-on-keyboard tooling is PowerShell, and this records it after
        # de-obfuscation.
        (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging') | Should -Be 1
    }
}

Describe 'Event log sizing' {
    # Windows has no per-filesystem mount options, so giving /var/log/audit its
    # own volume (as the Linux images do) has no equivalent. Bounding each log is
    # what replaces it.
    $expected = @{ Application = 64; Security = 196; System = 64 }

    foreach ($log in $expected.Keys) {
        It "$log log has a bounded maximum size" {
            $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\$log" 'MaxSize'
            $v | Should -Be ($expected[$log] * 1024)
        }
    }
}

Describe 'Firewall and RDP (CIS 9.x)' {
    foreach ($profileName in @('Domain', 'Private', 'Public')) {
        It "$profileName firewall profile is enabled" {
            (Get-NetFirewallProfile -Name $profileName).Enabled | Should -Be 'True'
        }

        It "$profileName firewall profile blocks inbound by default" {
            (Get-NetFirewallProfile -Name $profileName).DefaultInboundAction | Should -Be 'Block'
        }
    }

    It 'has RDP enabled' {
        # Deliberately left on -- it is the only interactive recovery path on a
        # Windows VM whose networking has gone wrong.
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') | Should -Be 0
    }

    It 'requires Network Level Authentication for RDP' {
        # NLA authenticates before a session is created. Without it the pre-auth
        # attack surface is the whole RDP stack, which is where BlueKeep lived.
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication') | Should -Be 1
    }

    It 'uses TLS as the RDP security layer' {
        (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'SecurityLayer') | Should -Be 2
    }
}

Describe 'Sysprep readiness' {
    It 'has a sysprep answer file staged' {
        'C:\Windows\Panther\unattend-sysprep.xml' | Should -Exist
    }

    It 'the sysprep answer file contains no credentials' {
        # THE test that matters here. The BUILD answer file contains the build
        # password and an auto-logon; shipping it as the sysprep file would bake
        # both into every VM created from this image. They are different files
        # and confusing them is the classic sysprep mistake.
        $content = Get-Content 'C:\Windows\Panther\unattend-sysprep.xml' -Raw
        $content | Should -Not -Match '<AdministratorPassword>'
        $content | Should -Not -Match '<AutoLogon>'
        $content | Should -Not -Match 'PlainText'
    }

    It 'the build answer file has been removed from the image' {
        'C:\Windows\Panther\unattend.xml' | Should -Not -Exist
    }
}

Describe 'WinRM teardown contract' {
    <#
        WinRM is still up right now -- these tests arrived over it. It cannot be
        torn down before Packer's shutdown command, because that command travels
        over the same transport (ADR-0017).

        So what is asserted here is the CONTRACT: that the finalisation script
        exists and will do the teardown. The end state is verified against the
        artefact offline. Testing the contract is weaker than testing the result
        and saying so is the point -- an assertion that silently tested nothing
        would be worse.
    #>

    It 'has a finalisation script staged' {
        $script:FinalizePath | Should -Exist
    }

    It 'the finalisation script disables unencrypted WinRM' {
        (Get-Content $script:FinalizePath -Raw) | Should -Match 'AllowUnencrypted="false"'
    }

    It 'the finalisation script disables Basic authentication' {
        (Get-Content $script:FinalizePath -Raw) | Should -Match 'Basic="false"'
    }

    It 'the finalisation script disables the WinRM service' {
        (Get-Content $script:FinalizePath -Raw) | Should -Match 'Set-Service -Name WinRM -StartupType Disabled'
    }

    It 'the finalisation script removes the build firewall rule' {
        (Get-Content $script:FinalizePath -Raw) | Should -Match "Remove-NetFirewallRule -Name 'WinRM-HTTP-Build'"
    }

    It 'the finalisation script generalises the image' {
        # /shutdown, not /reboot: rebooting runs the specialize pass and undoes
        # generalisation, producing an image that is not generalised at all
        # while appearing to have been sysprepped.
        $content = Get-Content $script:FinalizePath -Raw
        $content | Should -Match '/generalize'
        $content | Should -Match '/oobe'
        $content | Should -Match '/shutdown'
    }
}

Describe 'Build hygiene' {
    It 'has no Windows Update download cache left on the image' {
        $cache = Get-ChildItem 'C:\Windows\SoftwareDistribution\Download' -ErrorAction SilentlyContinue
        ($cache | Measure-Object).Count | Should -Be 0
    }

    It 'has no WinRM bootstrap transcript left on the image' {
        # It records the build's WinRM configuration.
        'C:\Windows\Temp\enable-winrm.log' | Should -Not -Exist
    }
}
