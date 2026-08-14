build {
  name = "windows"

  sources = [
    "source.qemu.windows",
    "source.vmware-iso.windows",
    "source.vsphere-iso.windows",
  ]

  // Same shape as the Linux build: prove the installer produced a reachable
  // machine before spending forty minutes on Windows Update.
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Output '--- os ---'",
      "Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture | Format-List",
      "Write-Output '--- installation type (expect Server Core) ---'",
      "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').InstallationType",
      "Write-Output '--- disk ---'",
      "Get-Volume | Where-Object DriveLetter -eq 'C' | Format-List DriveLetter, FileSystem, Size, SizeRemaining",
      "Write-Output '--- licensing (expect an evaluation channel) ---'",
      "cscript //nologo C:\\Windows\\System32\\slmgr.vbs /dli",
    ]
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/../../ansible/playbooks/windows-harden.yml"
    galaxy_file   = "${path.root}/../../ansible/requirements.yml"

    // Ansible reaches Windows over WinRM, not SSH, so the connection variables
    // are entirely different from the Linux build's — and Packer does not infer
    // them. Getting `ansible_shell_type` wrong is the usual cause of a play that
    // connects and then fails on every task.
    use_proxy = false

    extra_arguments = [
      "-e", "ansible_connection=winrm",
      "-e", "ansible_winrm_transport=basic",
      "-e", "ansible_winrm_server_cert_validation=ignore",
      "-e", "ansible_port=5985",
      "-e", "ansible_winrm_scheme=http",
      "-e", "ansible_shell_type=powershell",
      // Metadata for the in-image build-info file, so it matches manifest.json.
      "-e", "packer_image_name=${var.os_name}",
      "-e", "packer_image_version=${var.image_version}",
      "-e", "packer_git_commit=${var.git_commit}",
      "-e", "packer_iso_checksum=${var.iso_checksum}",
    ]

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_NOCOLOR=True",
      "ANSIBLE_CONFIG=${path.root}/../../ansible/ansible.cfg",
    ]
  }

  // Phase 4's Pester suite runs here, before the finalisation script tears down
  // WinRM and sysprep generalises the machine. Deliberately absent until it
  // exists — a stub that looks like a test gate is worse than none.

  post-processor "manifest" {
    output     = "${var.output_directory}/manifest.json"
    strip_path = true

    custom_data = {
      os_name             = var.os_name
      os_family           = var.os_family
      image_version       = var.image_version
      git_commit          = var.git_commit
      source_iso_url      = var.iso_url
      source_iso_checksum = var.iso_checksum
      build_timestamp     = timestamp()
      // Recorded in the manifest as well as in the image, so the phase 5
      // catalogue can refuse to publish evaluation media as production.
      licensing            = "evaluation"
      evaluation_days      = "180"
      windows_installation = "Server Core"
    }
  }
}
