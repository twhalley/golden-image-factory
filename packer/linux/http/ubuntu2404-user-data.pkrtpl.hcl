#cloud-config
# Ubuntu 24.04 autoinstall (subiquity) — phase 1.
#
# The Debian-family counterpart to rocky9-ks.cfg. It takes the SAME template
# variables, so both render from one `merge(local.ks_common, ...)` in
# sources.pkr.hcl and the source blocks stay identical apart from which file
# they point at.
#
# SCOPE is the same rule as the kickstart (ADR-0011): structure only. The
# filesystem layout is here because it cannot be retrofitted. Mount options,
# sshd policy, auditd and everything else are the phase 2 Ansible role's job, so
# one definition covers Rocky, Ubuntu and the Azure image alike.
#
# Served over Packer's HTTP server as /user-data alongside an empty /meta-data,
# which the nocloud datasource requires even when it has nothing to say.
autoinstall:
  version: 1

  # Stops subiquity asking for confirmation. Redundant with `autoinstall` on the
  # kernel command line, and harmless — belt and braces on the one prompt that
  # would silently turn an unattended build into a 45-minute timeout.
  interactive-sections: []

  locale: en_GB.UTF-8
  keyboard:
    layout: gb

  # UTC everywhere, matching the kickstart. An image carrying a site's timezone
  # cannot be used at another site.
  timezone: Etc/UTC

  identity:
    hostname: ${os_name}-golden
    realname: "Packer build account"
    username: ${build_username}
    # Locked. subiquity requires the key to be present; "!" is what an account
    # with no usable password looks like in /etc/shadow. late-commands runs
    # `usermod --lock` as well, because relying on one mechanism for "this
    # account cannot be logged into with a password" is how it ends up not being.
    password: "!"

  ssh:
    install-server: true
    # No password authentication, ever. The build account is key-only and the
    # key is ephemeral — see scripts/make-build-key.sh and ADR-0012.
    allow-pw: false
    authorized-keys:
      - "${ssh_public_key}"

  # Bring the image current at build time. What keeps it current is the monthly
  # scheduled rebuild in phase 6, not this.
  updates: all

  # subiquity would otherwise install a full set of server snaps.
  codecs:
    install: false
  drivers:
    install: false
  snaps: []

  packages:
    - openssh-server
    - sudo
    - chrony
    - python3
    - python3-apt
    - tar
    - rsync
    - ${guest_agent_package}

  # --- Storage ---------------------------------------------------------------
  # Deliberately explicit curtin config rather than `layout: {name: lvm}`, which
  # produces a single root LV. The separate filesystems below are the whole
  # point: they are what phase 2's mount options attach to, and a filesystem
  # that was not created separately cannot be given its own options later.
  #
  # Mirrors the Rocky layout volume for volume. Two honest differences:
  #   - ext4, not xfs. Both distributions get their own default; forcing xfs
  #     onto Ubuntu would be parity for its own sake.
  #   - msdos/MBR, matching the kickstart's `bootloader --location=mbr`. UEFI is
  #     a roadmap item for both, not a claim.
  storage:
    config:
      - id: disk0
        type: disk
        path: /dev/${install_disk}
        ptable: msdos
        wipe: superblock-recursive
        preserve: false
        grub_device: true

      - id: boot_part
        type: partition
        device: disk0
        size: 1G
        number: 1
        flag: boot
      - id: boot_fs
        type: format
        volume: boot_part
        fstype: ext4
        label: boot

      - id: pv_part
        type: partition
        device: disk0
        size: -1
        number: 2

      - id: vg_root
        type: lvm_volgroup
        name: vg_root
        devices: [pv_part]

      - {id: lv_root,   type: lvm_partition, name: lv_root,   volgroup: vg_root, size: 8G}
      - {id: lv_home,   type: lvm_partition, name: lv_home,   volgroup: vg_root, size: 1G}
      - {id: lv_var,    type: lvm_partition, name: lv_var,    volgroup: vg_root, size: 4G}
      - {id: lv_log,    type: lvm_partition, name: lv_log,    volgroup: vg_root, size: 2G}
      - {id: lv_audit,  type: lvm_partition, name: lv_audit,  volgroup: vg_root, size: 2G}
      - {id: lv_vartmp, type: lvm_partition, name: lv_vartmp, volgroup: vg_root, size: 1G}
      - {id: lv_tmp,    type: lvm_partition, name: lv_tmp,    volgroup: vg_root, size: 1G}

      - {id: fs_root,   type: format, volume: lv_root,   fstype: ext4}
      - {id: fs_home,   type: format, volume: lv_home,   fstype: ext4}
      - {id: fs_var,    type: format, volume: lv_var,    fstype: ext4}
      - {id: fs_log,    type: format, volume: lv_log,    fstype: ext4}
      - {id: fs_audit,  type: format, volume: lv_audit,  fstype: ext4}
      - {id: fs_vartmp, type: format, volume: lv_vartmp, fstype: ext4}
      - {id: fs_tmp,    type: format, volume: lv_tmp,    fstype: ext4}

      # Order matters: curtin mounts in the order given, so /var must exist
      # before /var/log, and /var/log before /var/log/audit.
      - {id: mount_root,   type: mount, device: fs_root,   path: /}
      - {id: mount_boot,   type: mount, device: boot_fs,   path: /boot}
      - {id: mount_home,   type: mount, device: fs_home,   path: /home}
      - {id: mount_var,    type: mount, device: fs_var,    path: /var}
      - {id: mount_log,    type: mount, device: fs_log,    path: /var/log}
      - {id: mount_audit,  type: mount, device: fs_audit,  path: /var/log/audit}
      - {id: mount_vartmp, type: mount, device: fs_vartmp, path: /var/tmp}
      - {id: mount_tmp,    type: mount, device: fs_tmp,    path: /tmp}

  # No swap. A golden image should not assume the memory profile of a workload
  # nobody has chosen yet. Stated in IMAGE-STANDARD.md as an omission rather
  # than left as an absence.
  swap:
    size: 0

  late-commands:
    # Passwordless sudo for the build account only, for the duration of the
    # build. The harden_linux role removes this file and the account in phase 2,
    # and phase 4's goss suite asserts both are gone.
    - |
      cat > /target/etc/sudoers.d/90-packer-build <<'EOF'
      # TEMPORARY — removed by the harden_linux role before the image is published.
      ${build_username} ALL=(ALL) NOPASSWD: ALL
      EOF
    - chmod 0440 /target/etc/sudoers.d/90-packer-build

    # Belt and braces on the locked password above.
    - curtin in-target --target=/target -- usermod --lock ${build_username}

    # The same identity metadata the kickstart writes, so a running VM from
    # either family answers "what am I?" identically. Phase 5's catalogue reads
    # the equivalent values out of manifest.json.
    - |
      cat > /target/etc/image-build-info <<EOF
      IMAGE_NAME=${os_name}
      IMAGE_VERSION=${image_version}
      GIT_COMMIT=${git_commit}
      SOURCE_ISO_CHECKSUM=${iso_checksum}
      BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      BUILDER=${builder_name}
      EOF
    - chmod 0444 /target/etc/image-build-info

    # cloud-init runs on first boot of the deployed VM and would otherwise
    # replay this build's identity — including the build account and its key —
    # onto every machine created from the image.
    - curtin in-target --target=/target -- cloud-init clean --logs --seed
