build {
  name = "linux"

  sources = [
    "source.qemu.linux",
    "source.vmware-iso.linux",
    "source.vsphere-iso.linux",
    "source.azure-arm.linux",
  ]

  // Phase 1 proves the installer produced a machine that boots and can be
  // reached. It deliberately asserts almost nothing about the contents — that
  // is phase 4's goss suite, and claiming it here would put the claim in the
  // wrong place. This step exists so a build that produces an unusable image
  // fails now rather than at test time.
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo '--- image build info ---'",
      "cat /etc/image-build-info",
      "echo '--- filesystem layout ---'",
      "findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS",
      "echo '--- selinux ---'",
      "getenforce",
    ]
    inline_shebang = "/bin/bash -e"
  }

  // Ansible hardening is phase 2. Deliberately absent rather than stubbed:
  // an empty provisioner block that looks like hardening is worse than none.

  post-processor "manifest" {
    output     = "${var.output_directory}/manifest.json"
    strip_path = true

    // Everything phase 5's catalogue needs to identify this artefact and decide
    // whether it is still fit to deploy. The source ISO checksum is included so
    // an image can be traced to the exact installation media it came from.
    custom_data = {
      os_name             = var.os_name
      os_family           = var.os_family
      image_version       = var.image_version
      git_commit          = var.git_commit
      source_iso_url      = var.iso_url
      source_iso_checksum = var.iso_checksum
      build_timestamp     = timestamp()
    }
  }
}
