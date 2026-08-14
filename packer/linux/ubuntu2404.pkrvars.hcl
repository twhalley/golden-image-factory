os_name   = "ubuntu2404"
os_family = "debian"

vmware_guest_os_type  = "ubuntu-64"
vsphere_guest_os_type = "ubuntu64Guest"

# Unlike Rocky 9.8, Ubuntu's published digest matches the file the servers
# actually send, and Canonical signs SHA256SUMS with a detached SHA256SUMS.gpg —
# so here the chain from vendor to image can be verified end to end rather than
# merely asserted. Contrast with ADR-0013.
iso_url      = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
iso_checksum = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"

# Ubuntu's live-server ISO boots through GRUB2, so this is genuinely different
# from Rocky's isolinux path — the same repo needs both, and neither pattern
# works on the other. Ubuntu dropped isolinux years before EL9 did.
#
# Rather than editing the existing menu entry, this drops to GRUB's command line
# with `c` and states the whole boot explicitly. That is more typing and much
# less fragile: it does not depend on which entry is selected, how many lines the
# entry has, or where the cursor lands when editing it — the three things that
# make an edit-the-entry boot command break on a point release.
#
# ds=nocloud, not nocloud-net: cloud-init deprecated the -net alias, and nocloud
# handles an http seed directly. The trailing slash on the URL is required —
# cloud-init appends "user-data" and "meta-data" to it.
boot_command = [
  "<wait5>c<wait3>",
  "linux /casper/vmlinuz autoinstall ds=\"nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\" ---<enter><wait3>",
  "initrd /casper/initrd<enter><wait3>",
  "boot<enter>"
]

boot_wait = "5s"

# Azure publishes Ubuntu itself; this is the marketplace base the azure-arm
# source starts from in phase 8. Note again that the Azure image shares this
# repo's Ansible roles and tests, not this installer configuration — there is no
# autoinstall in an Azure build.
azure_base_publisher = "Canonical"
azure_base_offer     = "ubuntu-24_04-lts"
azure_base_sku       = "server"
