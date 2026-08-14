// Windows Server 2022 — three sources.
//
// No azure-arm here, unlike the Linux templates, and that is a scope decision
// rather than an oversight: phase 8 publishes one Linux and one Windows image to
// the gallery, and the Windows Azure build starts from a marketplace base image
// with no answer file at all. It is added in phase 8 alongside the OIDC wiring,
// not stubbed here where it would be validated but meaningless.

locals {
  artefact_name = "${var.os_name}-${var.image_version}"

  // Rendered at build time with templatefile(), the same mechanism the Linux
  // kickstart and autoinstall use. Packer does NOT template the contents of
  // floppy_files or cd_files, so both go through the *_content variants — a
  // placeholder left in floppy_files would reach Windows Setup verbatim and
  // produce an image with an unusable Administrator password.
  // The answer file goes on a FLOPPY, the scripts on a CD.
  //
  // That split is not aesthetic. The first attempt put Autounattend.xml on the
  // provisioning CD, which reads better — no legacy floppy device on a modern
  // image — and Windows Setup did not find it: the build sat on the language
  // selection screen until the WinRM timeout, with a valid, well-formed answer
  // file sitting on an attached CD-ROM the whole time. Confirmed by
  // screenshotting the guest console (see RUNBOOK.md).
  //
  // Setup's search of removable media reliably covers a floppy; its CD-ROM
  // detection depends on media type and enumeration order in ways that are not
  // worth fighting. The floppy is 1.44 MB, exists only during the build, and is
  // detached before the artefact is written — so the objection to it was
  // cosmetic and the failure it caused was not.
  floppy_content = {
    "Autounattend.xml" = templatefile("answer/Autounattend.xml.pkrtpl.hcl", {
      winrm_password     = var.winrm_password
      admin_username     = var.admin_username
      computer_name      = var.computer_name
      windows_image_name = var.windows_image_name
    })
  }

  // The answer file is placed on BOTH the floppy and the CD, deliberately.
  //
  // Windows Setup searches removable media for Autounattend.xml, and which media
  // it can actually READ is not something to leave to chance. In WinPE on this
  // builder, `wmic logicaldisk` showed the floppy drive A: present but with no
  // volume label, while the CD showed its label correctly — the drive existed
  // and its filesystem did not mount. Packer writes the floppy with go-diskfs,
  // whose FAT12 BPB is not always accepted.
  //
  // Two copies of a 10 KB file removes an entire class of failure, and both
  // media are detached before the artefact is written. Setup uses whichever it
  // finds first; the content is identical either way.
  cd_content = {
    "/Autounattend.xml" = templatefile("answer/Autounattend.xml.pkrtpl.hcl", {
      winrm_password     = var.winrm_password
      admin_username     = var.admin_username
      computer_name      = var.computer_name
      windows_image_name = var.windows_image_name
    })
    "/enable-winrm.ps1" = file("scripts/enable-winrm.ps1")
  }

  // WinRM teardown AND sysprep, in one script, invoked as the shutdown command.
  //
  // Ordering is the whole game on Windows and this is where it is enforced. The
  // build needs WinRM over HTTP with Basic auth to reach the machine at all, and
  // that configuration must not survive into the image — but it cannot be torn
  // down from a provisioner, because Packer's next action is this very command
  // and it travels over WinRM. Disabling the transport from a task means sysprep
  // never runs and the image is never generalised.
  //
  // So harden_windows stages C:\Windows\image-finalize.ps1, and this runs it:
  // reverse the permissive settings, remove the listener and firewall rules,
  // disable the service, then sysprep /generalize /oobe /shutdown. The script
  // severs its own transport and powers off, so nothing needs to outlive its own
  // effects. Same shape as the Linux finalisation script (ADR-0015, ADR-0017).
  //
  // Falls back to bare sysprep if the script is absent, so a build with the
  // Ansible provisioner disabled still generalises and terminates rather than
  // hanging for the full shutdown_timeout.
  sysprep_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"if (Test-Path 'C:/Windows/image-finalize.ps1') { & 'C:/Windows/image-finalize.ps1' } else { & 'C:/Windows/System32/Sysprep/sysprep.exe' /generalize /oobe /shutdown /quiet /mode:vm }\""
}

// ---------------------------------------------------------------------------
// qemu — the CI builder.
// ---------------------------------------------------------------------------
source "qemu" "windows" {
  vm_name          = "${local.artefact_name}.qcow2"
  output_directory = "${var.output_directory}/qemu-${local.artefact_name}"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  accelerator = "kvm"
  cpus        = var.cpus
  memory      = var.memory

  // machine_type "pc" (i440fx), NOT "q35" as the Linux sources use.
  //
  // q35 is an ICH9 platform and has NO ISA floppy controller. QEMU accepts
  // `-fda` on it without complaint and the guest sees nothing — so Windows Setup
  // finds no answer file and sits on the language selection screen until the
  // WinRM timeout. Diagnosed by screenshotting the console: a valid answer file,
  // correctly written to a floppy image that was correctly attached, on a
  // machine with no controller able to read it.
  //
  // i440fx has the controller, and Windows Server 2022 runs on it perfectly
  // well. It also brings PIIX3 IDE, which Windows has in-box drivers for, so the
  // disk_interface choice below stops being a compromise and is simply correct
  // for this platform.
  machine_type = "pc"

  disk_size = var.disk_size
  format    = "qcow2"

  // "ide" and e1000, NOT the virtio pair the Linux images use.
  //
  // Windows Setup ships no in-box virtio driver, so a virtio disk is simply not
  // visible to the installer — the build fails at partitioning with a message
  // that does not mention drivers. The alternatives are attaching the virtio-win
  // ISO as a second CD and wiring driver paths into the answer file, or using
  // hardware Windows already supports. The second is chosen here: it removes a
  // download, a second CD device and a whole class of failure, at the cost of
  // build-time I/O throughput that does not affect the published artefact.
  //
  // "ide" rather than "sata": QEMU has no `if=sata` bus type and rejects it
  // outright ("unsupported bus type 'sata'"), which surfaces as an unexplained
  // "Qemu failed to start" unless you run with PACKER_LOG=1. On the q35 machine
  // type `if=ide` is implemented by the ICH9 AHCI controller — so this IS SATA,
  // under the name QEMU actually accepts.
  //
  // A production vSphere template would install VMware Tools and convert to
  // paravirtual adapters after installation; that is a post-install step, not a
  // build one.
  disk_interface = "ide"
  net_device     = "e1000"

  headless = var.headless

  floppy_content = local.floppy_content
  cd_content     = local.cd_content
  cd_label       = "PROVISION"

  // No boot_command at all. Windows Setup searches removable media for
  // Autounattend.xml by itself, which removes the most fragile part of an
  // ISO-based build — compare the isolinux and GRUB keystroke sequences the two
  // Linux images needed, both of which had to be settled by screenshotting the
  // console mid-build.
  boot_wait = "3s"

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.winrm_password
  winrm_timeout  = var.winrm_timeout
  winrm_insecure = true
  winrm_use_ssl  = false

  shutdown_command = local.sysprep_command
  shutdown_timeout = "45m"

  qemuargs = [
    ["-cpu", "host"]
  ]
}

// ---------------------------------------------------------------------------
// vmware-iso — VMware Workstation, executed locally.
// ---------------------------------------------------------------------------
source "vmware-iso" "windows" {
  vm_name          = local.artefact_name
  output_directory = "${var.output_directory}/vmware-${local.artefact_name}"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  guest_os_type = "windows2019srvnext-64"
  version       = "21"

  cpus   = var.cpus
  memory = var.memory

  disk_size            = var.disk_size
  disk_adapter_type    = "lsisas1068"
  disk_type_id         = "0"
  network_adapter_type = "e1000e"

  // lsisas1068 and e1000e rather than the pvscsi/vmxnet3 used for Linux. Windows
  // Setup has no in-box driver for either paravirtual device, so a pvscsi disk
  // is simply not visible to the installer and the build fails at partitioning
  // with an unhelpful message. VMware Tools installs the paravirtual drivers
  // afterwards; converting the adapters is a post-install step, not a build one.
  headless = var.headless

  floppy_content = local.floppy_content
  cd_content     = local.cd_content
  cd_label       = "PROVISION"
  boot_wait      = "3s"

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.winrm_password
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.sysprep_command
  shutdown_timeout = "45m"

  vmx_data = {
    "disk.EnableUUID"               = "TRUE"
    "isolation.tools.copy.disable"  = "TRUE"
    "isolation.tools.paste.disable" = "TRUE"
    "isolation.tools.dnd.disable"   = "TRUE"
  }
}

// ---------------------------------------------------------------------------
// vsphere-iso — validated on every PR, executed in phase 9.
// ---------------------------------------------------------------------------
source "vsphere-iso" "windows" {
  vm_name = local.artefact_name

  vcenter_server      = var.vcenter_server
  username            = var.vcenter_username
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure

  datacenter = var.vsphere_datacenter
  cluster    = var.vsphere_cluster
  datastore  = var.vsphere_datastore
  folder     = var.vsphere_folder

  vm_version           = 21
  guest_os_type        = "windows2019srvNext_64Guest"
  firmware             = "bios"
  CPUs                 = var.cpus
  RAM                  = var.memory
  disk_controller_type = ["lsilogic-sas"]

  storage {
    disk_size             = var.disk_size
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.vsphere_network
    network_card = "e1000e"
  }

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  floppy_content = local.floppy_content
  cd_content     = local.cd_content
  boot_wait      = "3s"

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.winrm_password
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.sysprep_command
  shutdown_timeout = "45m"

  convert_to_template = true
  remove_cdrom        = true
}
