// Four sources, one build, one set of provisioning code.
//
// What differs between them is genuinely platform-specific and nothing else:
// the disk device the installer writes to, the guest agent that matches the
// hypervisor, and how the artefact is stored. The kickstart, the Ansible roles
// and the test suites are shared. Where a platform cannot share something, the
// README says so rather than implying parity — see azure-arm at the bottom.

locals {
  // Values every rendering of the unattended-install file needs. Both the
  // kickstart and the autoinstall template take the SAME variable set, which is
  // what lets one source block serve either family without branching.
  ks_common = {
    os_name        = var.os_name
    image_version  = var.image_version
    git_commit     = var.git_commit
    iso_checksum   = var.iso_checksum
    build_username = var.build_username
    ssh_public_key = var.ssh_public_key
  }

  artefact_name = "${var.os_name}-${var.image_version}"

  // Finalisation and shutdown in one action, run as root.
  //
  // This is not a stylistic choice. harden_linux must remove the build account,
  // and Packer is logged in AS that account — deleting it from a provisioner
  // breaks the connection Packer needs to shut the machine down, failing a build
  // that did everything right. The script runs as root via sudo, removes the
  // account, wipes machine-id, SSH host keys and build traces, then powers off,
  // so nothing needs to survive its own effects. See ADR-0015.
  //
  // Falls back to a plain shutdown if the script is absent, so a build with the
  // Ansible provisioner disabled still terminates instead of hanging for the
  // full shutdown_timeout.
  shutdown_command = "echo '' | sudo -S bash -c 'if [ -x /usr/local/sbin/image-finalize.sh ]; then exec /usr/local/sbin/image-finalize.sh; else exec /sbin/shutdown -P now; fi'"

  // Per-builder differences are exactly two things: the disk the installer
  // writes to, and the guest agent matching the hypervisor.
  per_builder = {
    qemu = {
      install_disk        = "vda"
      guest_agent_package = "qemu-guest-agent"
      builder_name        = "qemu"
    }
    vmware = {
      install_disk        = "sda"
      guest_agent_package = "open-vm-tools"
      builder_name        = "vmware-iso"
    }
    vsphere = {
      install_disk        = "sda"
      guest_agent_package = "open-vm-tools"
      builder_name        = "vsphere-iso"
    }
  }

  // RHEL serves one kickstart; Debian serves cloud-init's user-data plus an
  // empty meta-data, which the nocloud datasource requires even with nothing in
  // it. Both branches of each conditional are evaluated by HCL, which is fine
  // precisely because both templates accept the same variables.
  http_qemu = var.os_family == "rhel" ? {
    "/ks.cfg" = templatefile("http/rocky9-ks.cfg.pkrtpl.hcl", merge(local.ks_common, local.per_builder.qemu))
    } : {
    "/user-data" = templatefile("http/ubuntu2404-user-data.pkrtpl.hcl", merge(local.ks_common, local.per_builder.qemu))
    "/meta-data" = ""
  }

  http_vmware = var.os_family == "rhel" ? {
    "/ks.cfg" = templatefile("http/rocky9-ks.cfg.pkrtpl.hcl", merge(local.ks_common, local.per_builder.vmware))
    } : {
    "/user-data" = templatefile("http/ubuntu2404-user-data.pkrtpl.hcl", merge(local.ks_common, local.per_builder.vmware))
    "/meta-data" = ""
  }

  http_vsphere = var.os_family == "rhel" ? {
    "/ks.cfg" = templatefile("http/rocky9-ks.cfg.pkrtpl.hcl", merge(local.ks_common, local.per_builder.vsphere))
    } : {
    "/user-data" = templatefile("http/ubuntu2404-user-data.pkrtpl.hcl", merge(local.ks_common, local.per_builder.vsphere))
    "/meta-data" = ""
  }
}

// ---------------------------------------------------------------------------
// qemu — the CI builder. Runs on every PR (phase 6). virtio throughout.
// ---------------------------------------------------------------------------
source "qemu" "linux" {
  vm_name          = "${local.artefact_name}.qcow2"
  output_directory = "${var.output_directory}/qemu-${local.artefact_name}"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  // KVM where it exists. GitHub-hosted runners may not expose /dev/kvm, in
  // which case this falls back to TCG software emulation and gets much slower
  // rather than failing — phase 6 measures it and the README states the number
  // instead of implying CI builds are fast.
  accelerator  = "kvm"
  machine_type = "q35"
  cpus         = var.cpus
  memory       = var.memory

  disk_size      = var.disk_size
  disk_interface = "virtio"
  disk_discard   = "unmap"
  format         = "qcow2"
  net_device     = "virtio-net"

  headless = var.headless

  http_content = local.http_qemu

  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  communicator         = "ssh"
  ssh_username         = var.build_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = "10m"

  // -cpu host passes through the physical CPU's features, which roughly halves
  // install time under KVM. Harmless under TCG, where it is ignored.
  qemuargs = [
    ["-cpu", "host"]
  ]
}

// ---------------------------------------------------------------------------
// vmware-iso — VMware Workstation, executed locally. Real VMware, not a claim.
// ---------------------------------------------------------------------------
source "vmware-iso" "linux" {
  vm_name          = local.artefact_name
  output_directory = "${var.output_directory}/vmware-${local.artefact_name}"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  guest_os_type = var.vmware_guest_os_type
  version       = "21" // Workstation 17 virtual hardware

  cpus   = var.cpus
  memory = var.memory

  disk_size            = var.disk_size
  disk_adapter_type    = "pvscsi"
  disk_type_id         = "0" // single growable virtual disk
  network_adapter_type = "vmxnet3"

  // pvscsi and vmxnet3 rather than the lsilogic/e1000 defaults, because those
  // are what a vSphere estate actually runs and EL9 ships both drivers in its
  // installer initrd. Getting this wrong is visible to anyone who runs vSphere
  // daily, and it is the same choice phase 9 needs.

  headless = var.headless

  http_content = local.http_vmware

  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  communicator         = "ssh"
  ssh_username         = var.build_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = "10m"

  // Only settings Packer does not already derive from the fields above.
  // virtualHW.version, ethernet0.virtualDev and scsi0.virtualDev are set by
  // `version`, `network_adapter_type` and `disk_adapter_type` respectively;
  // repeating them here makes Packer warn that the build may behave
  // unpredictably, which it does not do for decoration.
  vmx_data = {
    // Required for in-guest disk serial numbers, which vSphere and any
    // multipath-aware tooling depend on. Off by default; costs nothing.
    "disk.EnableUUID" = "TRUE"

    // Host-guest clipboard and drag-and-drop are a data path out of the guest
    // that a server image has no use for. CIS-adjacent, and cheap to close here
    // rather than argue about later.
    "isolation.tools.copy.disable"  = "TRUE"
    "isolation.tools.paste.disable" = "TRUE"
    "isolation.tools.dnd.disable"   = "TRUE"
  }
}

// ---------------------------------------------------------------------------
// vsphere-iso — the production shape. Validated on every PR; executed against
// the nested ESXi + VCSA evaluation lab in phase 9. Until that build log is
// committed, the README reality table says "validate only" and means it.
// ---------------------------------------------------------------------------
source "vsphere-iso" "linux" {
  vm_name = local.artefact_name

  vcenter_server      = var.vcenter_server
  username            = var.vcenter_username
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure

  datacenter = var.vsphere_datacenter
  cluster    = var.vsphere_cluster
  datastore  = var.vsphere_datastore
  folder     = var.vsphere_folder

  // Hardware 21 is vSphere 8. Set explicitly: the plugin's default tracks the
  // cluster's, which makes the artefact depend on where it happened to build.
  vm_version           = 21
  guest_os_type        = var.vsphere_guest_os_type
  firmware             = "bios"
  CPUs                 = var.cpus
  RAM                  = var.memory
  RAM_reserve_all      = false
  disk_controller_type = ["pvscsi"]

  storage {
    disk_size             = var.disk_size
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.vsphere_network
    network_card = "vmxnet3"
  }

  iso_paths    = []
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  http_content = local.http_vsphere

  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  communicator         = "ssh"
  ssh_username         = var.build_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = "10m"

  // A template, not a powered-off VM — the distribution unit a vSphere estate
  // expects. Content library publishing is phase 9, alongside the real lab.
  convert_to_template = true
  remove_cdrom        = true
}

// ---------------------------------------------------------------------------
// azure-arm — a second publishing target, phase 8.
//
// THIS SOURCE HAS NO KICKSTART, AND THAT IS NOT AN OVERSIGHT. azure-arm builds
// from a marketplace base image rather than an ISO, which is the correct Azure
// pattern; there is no installer to answer. The consequence, stated here and in
// the README rather than left for an interviewer to find: the Azure image shares
// this repo's Ansible roles and test suites with the VMware images, but not
// their installer configuration. The images are equivalent in policy, not
// identical in bits.
// ---------------------------------------------------------------------------
source "azure-arm" "linux" {
  // OIDC federated credential — there is no client secret anywhere in this repo
  // or in GitHub secrets. The token comes from the Actions runtime.
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = var.azure_client_id
  client_jwt      = var.azure_oidc_token

  os_type         = "Linux"
  image_publisher = var.azure_base_publisher
  image_offer     = var.azure_base_offer
  image_sku       = var.azure_base_sku

  location = var.azure_location
  vm_size  = var.azure_vm_size

  managed_image_name                = local.artefact_name
  managed_image_resource_group_name = var.azure_resource_group

  shared_image_gallery_destination {
    subscription         = var.azure_subscription_id
    resource_group       = var.azure_resource_group
    gallery_name         = var.azure_gallery_name
    image_name           = var.os_name
    image_version        = var.image_version
    replication_regions  = [var.azure_location]
    storage_account_type = "Standard_LRS"
  }

  // Cost control is not optional here. One region, no replication fan-out,
  // Standard_LRS, smallest viable build VM. Teardown is in docs/RUNBOOK.md and
  // is actually run — a follow-up az query proves the resources are gone.
  azure_tags = {
    project    = "golden-image-factory"
    managed_by = "packer"
    ephemeral  = "true"
  }

  communicator = "ssh"
  ssh_username = var.build_username
}
