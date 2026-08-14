#version=RHEL9
# Rocky 9 kickstart — phase 1.
#
# Templated by Packer (templatefile) and served over Packer's built-in HTTP
# server, so the ephemeral build public key is injected at build time rather
# than committed. Rendered content is never written to disk in the repo.
#
# SCOPE. This file does structure, not policy. Anything that must exist at
# install time and cannot be retrofitted later lives here — chiefly the
# filesystem layout. Everything that can be changed on a running system is
# phase 2's Ansible role, so that the hardening is expressed once and applies
# equally to the Azure image, which has no kickstart at all.
#
# The split is deliberate and it is the boundary to explain: separate
# filesystems are a partitioning decision, mount options are a configuration
# decision.

text
eula --agreed
reboot --eject

# --- Package source ----------------------------------------------------------
# This is a network install from boot.iso, which carries the installer but no
# packages. That is not the usual Packer pattern and it is a deliberate choice:
# the published checksum for Rocky 9.8's minimal.iso does not match the file the
# mirrors actually serve, so minimal.iso cannot be verified. boot.iso and dvd.iso
# both match their digests. See ADR-0013.
#
# Consequences, stated rather than discovered: the build needs network access to
# a package mirror, and two builds from the same commit on different days can
# pick up different package versions. The second point matters less than it
# looks — the image runs a full `dnf upgrade` during %post regardless, so it was
# never going to be bit-reproducible across time. What pins reproducibility here
# is the manifest and the SBOM (phase 7) recording exactly what landed, not the
# hope that the inputs never move.
url --url="https://download.rockylinux.org/pub/rocky/9.8/BaseOS/x86_64/os/"
repo --name="appstream" --baseurl="https://download.rockylinux.org/pub/rocky/9.8/AppStream/x86_64/os/"

# --- Localisation ------------------------------------------------------------
# UTC everywhere. An image that carries a site's timezone is an image that
# cannot be used at another site.
keyboard --vckeymap=gb --xlayouts='gb'
lang en_GB.UTF-8
timezone Etc/UTC --utc

# --- Network -----------------------------------------------------------------
# --device=link takes the first interface that has carrier, which keeps this
# working across qemu (virtio-net), Workstation and vSphere (vmxnet3) without
# hardcoding an interface name.
network --bootproto=dhcp --device=link --activate --onboot=on
network --hostname=${os_name}-golden

# --- Security ----------------------------------------------------------------
# SELinux stays enforcing. Disabling it is the single most common shortcut in
# a golden image and it silently invalidates a large part of any CIS claim.
selinux --enforcing
firewall --enabled --service=ssh

# Root has no usable password and cannot log in over SSH. The build account is
# the only way in, it authenticates by key only, and phase 2 removes it before
# the image is published.
rootpw --lock
user --name=${build_username} --groups=wheel --lock --gecos "Packer build account"
sshkey --username=${build_username} "${ssh_public_key}"

# --- Storage -----------------------------------------------------------------
# Separate filesystems for the paths CIS Level 1 expects to carry their own
# mount options, plus the ones that protect the root filesystem from a log or
# audit flood. /var/log/audit is separate specifically so that a full audit
# volume cannot take the system down with it.
#
# No swap. A golden image should not assume the memory profile of the workload
# that will run on it; swap is a deployment-time decision. Documented in
# IMAGE-STANDARD.md rather than left as an absence.
ignoredisk --only-use=${install_disk}
clearpart --all --initlabel --drives=${install_disk}
bootloader --location=mbr --boot-drive=${install_disk} --append="crashkernel=no net.ifnames=0 biosdevname=0"
zerombr

part /boot --fstype=xfs --size=1024 --label=boot --ondisk=${install_disk}
part pv.01 --grow --ondisk=${install_disk}
volgroup vg_root pv.01

logvol /              --vgname=vg_root --name=lv_root     --fstype=xfs --size=8192
logvol /home          --vgname=vg_root --name=lv_home     --fstype=xfs --size=1024
logvol /var           --vgname=vg_root --name=lv_var      --fstype=xfs --size=4096
logvol /var/log       --vgname=vg_root --name=lv_log      --fstype=xfs --size=2048
logvol /var/log/audit --vgname=vg_root --name=lv_audit    --fstype=xfs --size=2048
logvol /var/tmp       --vgname=vg_root --name=lv_vartmp   --fstype=xfs --size=1024
logvol /tmp           --vgname=vg_root --name=lv_tmp      --fstype=xfs --size=1024

# --- Packages ----------------------------------------------------------------
# Minimal, plus exactly what is needed to be managed and to build. Nothing is
# installed here "because it is usually handy" — every package is attack surface
# that has to be patched for the life of the image.
#
# Note: the %packages section does not support trailing comments on a package
# line — anaconda treats the whole line as a package name. Comments go on their
# own line.
#
# python3 is Ansible's interpreter (phase 2); python3-libselinux lets Ansible
# manage SELinux contexts; tar is required by Ansible's unarchive path.
# ${guest_agent_package} is substituted per source: the hypervisor guest agent
# matching the platform being built for, and only that one.
%packages --ignoremissing --excludedocs
@^minimal-environment
openssh-server
sudo
chrony
python3
python3-libselinux
tar
rsync
dnf-utils
${guest_agent_package}

-plymouth
-iwl*-firmware
-alsa-*
-biosdevname
-dracut-config-rescue
%end

# --- Post-install ------------------------------------------------------------
# Chrooted into the installed system. Kept to the minimum needed for Packer to
# connect and for Ansible to run; hardening belongs in phase 2.
%post --log=/root/ks-post.log

# Passwordless sudo for the build account only, and only for the duration of the
# build. Phase 2's cleanup removes this file along with the account itself. It is
# written with an explicit mode because the default umask in %post is not
# guaranteed and sudo refuses to read a world-writable file.
install -d -m 0750 /etc/sudoers.d
cat > /etc/sudoers.d/90-packer-build <<'EOF'
# TEMPORARY — removed by the harden_linux role before the image is published.
${build_username} ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/90-packer-build

# requiretty would break Ansible's non-interactive become.
sed -i 's/^\(Defaults\s*requiretty\)/# \1/' /etc/sudoers || true

# Record what produced this image, before anything else can claim to have.
# Phase 5's catalogue reads the same values out of manifest.json; this file is
# the copy that travels inside the image itself.
cat > /etc/image-build-info <<EOF
IMAGE_NAME=${os_name}
IMAGE_VERSION=${image_version}
GIT_COMMIT=${git_commit}
SOURCE_ISO_CHECKSUM=${iso_checksum}
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILDER=${builder_name}
EOF
chmod 0444 /etc/image-build-info

# Bring the image up to date at build time. The monthly scheduled rebuild in
# phase 6 is what keeps it that way; this only sets the starting point.
dnf -y upgrade --refresh
dnf -y clean all

systemctl enable sshd chronyd

%end
