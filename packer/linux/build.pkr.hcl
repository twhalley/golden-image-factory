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
  provisioner "shell" { // remote_folder, because /tmp is noexec after phase 2.
    //
    // Packer's shell provisioner uploads its script to /tmp and executes it.
    // harden_linux mounts /tmp with noexec (CIS 1.1.2), so from that point on
    // every shell provisioner fails with:
    //     bash: line 1: /tmp/script_NNNN.sh: Permission denied
    // and exit status 126, which looks like a broken script rather than a
    // working mount option.
    //
    // This is the hardening doing exactly what it is supposed to do, to the
    // build tooling. /home is mounted nodev,nosuid but deliberately NOT noexec
    // (see harden_linux defaults), so the build account's home works and the
    // control stays intact. Weakening /tmp to make the tooling happy would be
    // the wrong way round, and is precisely the compromise this repo argues
    // against making.
    remote_folder = "/home/${var.build_username}"

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

  // ---------------------------------------------------------------------
  // Phase 4 — the test gate.
  //
  // Runs INSIDE the guest, as the last thing before shutdown, so it tests the
  // built image rather than the template that claims to build it. A failing
  // assertion fails the build and no artefact is produced.
  //
  // It runs BEFORE the finalisation script (which removes the build account and
  // the SSH host keys at shutdown), so it cannot assert those removals — see
  // ADR-0015 and the header of tests/goss/shared.yaml. Stated there rather than
  // silently omitted.
  // ---------------------------------------------------------------------
  provisioner "shell" { // remote_folder, because /tmp is noexec after phase 2.
    //
    // Packer's shell provisioner uploads its script to /tmp and executes it.
    // harden_linux mounts /tmp with noexec (CIS 1.1.2), so from that point on
    // every shell provisioner fails with:
    //     bash: line 1: /tmp/script_NNNN.sh: Permission denied
    // and exit status 126, which looks like a broken script rather than a
    // working mount option.
    //
    // This is the hardening doing exactly what it is supposed to do, to the
    // build tooling. /home is mounted nodev,nosuid but deliberately NOT noexec
    // (see harden_linux defaults), so the build account's home works and the
    // control stays intact. Weakening /tmp to make the tooling happy would be
    // the wrong way round, and is precisely the compromise this repo argues
    // against making.
    remote_folder = "/home/${var.build_username}"

    // The file provisioner will not create the destination directory, and
    // uploading a directory into a path that does not exist fails with
    // "scp: /tmp/goss/: Not a directory" — which reads like a permissions
    // problem and is not one.
    inline         = ["mkdir -p /tmp/goss"]
    inline_shebang = "/bin/bash -e"
  }

  provisioner "file" {
    source      = "${path.root}/../../tests/goss/"
    destination = "/tmp/goss"
  }

  provisioner "shell" { // remote_folder, because /tmp is noexec after phase 2.
    //
    // Packer's shell provisioner uploads its script to /tmp and executes it.
    // harden_linux mounts /tmp with noexec (CIS 1.1.2), so from that point on
    // every shell provisioner fails with:
    //     bash: line 1: /tmp/script_NNNN.sh: Permission denied
    // and exit status 126, which looks like a broken script rather than a
    // working mount option.
    //
    // This is the hardening doing exactly what it is supposed to do, to the
    // build tooling. /home is mounted nodev,nosuid but deliberately NOT noexec
    // (see harden_linux defaults), so the build account's home works and the
    // control stays intact. Weakening /tmp to make the tooling happy would be
    // the wrong way round, and is precisely the compromise this repo argues
    // against making.
    remote_folder = "/home/${var.build_username}"

    inline = [
      "set -euo pipefail",
      "echo '--- installing goss ---'",
      "curl -fsSL -o /tmp/goss.tar.gz https://github.com/goss-org/goss/releases/download/v${var.goss_version}/goss_${var.goss_version}_linux_x86_64.tar.gz",
      "echo \"${var.goss_sha256}  /tmp/goss.tar.gz\" | sha256sum -c -",
      // Extracted to its own directory: /tmp/goss is the uploaded test suite,
      // and tar would otherwise try to write the `goss` binary over it —
      // "tar: goss: Cannot open: File exists".
      "mkdir -p /tmp/goss-bin",
      "tar xzf /tmp/goss.tar.gz -C /tmp/goss-bin goss",
      "sudo install -m 0755 /tmp/goss-bin/goss /usr/local/bin/goss",
      // Absolute path from here on. sudo resets PATH to its compiled-in
      // secure_path, which on RHEL does not include /usr/local/bin — so
      // `sudo goss` fails with "command not found" even though `goss` works.
      "/usr/local/bin/goss --version",
    ]
    inline_shebang = "/bin/bash -e"
  }

  provisioner "shell" { // remote_folder, because /tmp is noexec after phase 2.
    //
    // Packer's shell provisioner uploads its script to /tmp and executes it.
    // harden_linux mounts /tmp with noexec (CIS 1.1.2), so from that point on
    // every shell provisioner fails with:
    //     bash: line 1: /tmp/script_NNNN.sh: Permission denied
    // and exit status 126, which looks like a broken script rather than a
    // working mount option.
    //
    // This is the hardening doing exactly what it is supposed to do, to the
    // build tooling. /home is mounted nodev,nosuid but deliberately NOT noexec
    // (see harden_linux defaults), so the build account's home works and the
    // control stays intact. Weakening /tmp to make the tooling happy would be
    // the wrong way round, and is precisely the compromise this repo argues
    // against making.
    remote_folder = "/home/${var.build_username}"

    // Two runs on purpose. The first writes a machine-readable report that is
    // pulled out of the guest as the compliance artefact; the second prints
    // human-readable output into the build log and is what actually fails the
    // build. `set -o pipefail` matters — without it the exit status would be
    // tee's, and the gate would pass while reporting failures.
    inline = [
      "set -euo pipefail",
      "cd /tmp/goss",
      "echo '--- goss: machine-readable compliance report ---'",
      "sudo /usr/local/bin/goss -g /tmp/goss/${var.os_name}.yaml validate --format json --format-options pretty > /tmp/goss-report.json || true",
      "echo '--- goss: gate ---'",
      "sudo /usr/local/bin/goss -g /tmp/goss/${var.os_name}.yaml validate --format documentation",
    ]
    inline_shebang = "/bin/bash -e"
  }

  provisioner "file" {
    // Out of the guest and into the build directory, so the compliance report
    // survives the VM. Phase 5's catalogue entry references it; phase 7 signs it.
    direction   = "download"
    source      = "/tmp/goss-report.json"
    destination = "${var.output_directory}/goss-${var.os_name}-${var.image_version}.json"
  }


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
