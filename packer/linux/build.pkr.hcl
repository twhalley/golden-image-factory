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
      # Mandatory access control is NOT the same control on both families, and
      # this step is shared by all of them. RHEL ships SELinux and `getenforce`;
      # Ubuntu ships AppArmor and has no `getenforce` at all — assuming otherwise
      # failed a build here with exit 127 after a perfectly good install.
      #
      # Reporting whichever is present, and failing if neither is, keeps the
      # check meaningful on both rather than lowering it to something that passes
      # everywhere. It also fixes the vocabulary for phase 2: the image standard
      # can claim "mandatory access control enforcing", which is true of both,
      # and must not claim "SELinux enforcing", which is true of one.
      "echo '--- mandatory access control ---'",
      "if command -v getenforce >/dev/null 2>&1; then",
      "  echo \"SELinux: $(getenforce)\"",
      "  test \"$(getenforce)\" = 'Enforcing'",
      "elif command -v aa-enabled >/dev/null 2>&1; then",
      "  echo \"AppArmor: $(aa-enabled)\"",
      "  test \"$(aa-enabled)\" = 'Yes'",
      "else",
      "  echo 'No mandatory access control tooling found' >&2; exit 1",
      "fi",
    ]
    inline_shebang = "/bin/bash -e"
  }

  // Phase 2 — hardening. One playbook and one role for every target, including
  // azure-arm, which has no installer file of its own and therefore gets its
  // entire configuration from here (ADR-0011).
  provisioner "ansible" {
    playbook_file = "${path.root}/../../ansible/playbooks/linux-harden.yml"
    galaxy_file   = "${path.root}/../../ansible/requirements.yml"

    // Ansible defaults to checking host keys against a known_hosts file that
    // cannot possibly contain a VM created ninety seconds ago.
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_NOCOLOR=True",
      "ANSIBLE_CONFIG=${path.root}/../../ansible/ansible.cfg",
      "ANSIBLE_FORCE_COLOR=0",
    ]

    extra_arguments = [
      "--extra-vars", "harden_linux_build_username=${var.build_username}",
    ]
  }

  // Phase 4's goss suite runs here, before finalisation removes the build
  // account. Deliberately absent until phase 2 is proven — a stub that looks
  // like a test gate is worse than none.

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
