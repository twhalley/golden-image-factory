os_name   = "rocky9"
os_family = "rhel"

# boot.iso, NOT minimal.iso — and that is a deliberate integrity decision, not a
# preference. On 2026-08-14 every reachable Rocky mirror served a
# Rocky-9.8-x86_64-minimal.iso of 2,755,067,904 bytes while the published
# CHECKSUM manifest claimed 1,480,048,640 bytes, and the served file's ISO
# volume label read "Rocky-9-8-x86_64-dvd". The manifest's minimal entry carries
# the same byte count as its boot entry, which is what a stale entry looks like.
#
# boot.iso and dvd.iso both match their published digests exactly. So this image
# is built from installation media whose integrity can actually be verified.
# Full write-up: evidence/rocky98-minimal-iso-checksum-mismatch-2026-08-14.md
# and ADR-0013.
iso_url      = "https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-boot.iso"
iso_checksum = "sha256:d6eeefdc8437c593d41a3150fcca4a734c55642ed472eecdda99720bb1370881"

# Rocky 9.8's BIOS boot path uses **isolinux**, not GRUB2. This was established by
# screenshotting the guest console over VNC mid-build rather than assumed — the
# menu prints "Press Tab for full configuration options on menu items", and Tab
# exposes the editable kernel command line:
#
#   > vmlinuz initrd=initrd.img inst.stage2=hd:LABEL=Rocky-9-8-x86_64-dvd quiet
#
# So the GRUB `e` / `<down><end>` / Ctrl-X sequence that EL9 documentation implies
# does not apply here, and a boot command written from that assumption fails
# silently: the installer simply sits at the menu until the 45-minute SSH timeout,
# with a 197 KB disk image as the only clue. See ADR-0009 and RUNBOOK.md for how
# to capture the console when this happens.
#
# "Install Rocky Linux 9.8" is the FIRST entry and is already selected, so there
# is no <up>; pressing it would move the selection off the entry we want.
#
# Only inst.ks is appended. The package source is declared by the kickstart's
# `url` directive rather than an inst.repo= argument here, so the repository
# configuration lives in one place and is visible where the packages are chosen.
boot_command = [
  "<tab><wait>",
  " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
  "<enter><wait>"
]

# 10s, not 5s: isolinux must have drawn the menu before Tab means anything, and a
# keystroke sent early is simply discarded.
boot_wait = "10s"
