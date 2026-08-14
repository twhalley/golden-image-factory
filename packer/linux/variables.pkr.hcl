// ---------------------------------------------------------------------------
// Image identity
// ---------------------------------------------------------------------------

variable "os_name" {
  type        = string
  description = "Short image name, used in artefact paths and the catalogue. e.g. rocky9"
}

variable "os_family" {
  type        = string
  description = "Installer family. Selects which unattended-install file is served: rhel (kickstart) or debian (autoinstall)."

  validation {
    condition     = contains(["rhel", "debian"], var.os_family)
    error_message = "The os_family must be either rhel or debian."
  }
}

variable "image_version" {
  type        = string
  default     = "0.1.0"
  description = "Semver for this image. Phase 5 drives this from the catalogue; until then it is set per build."
}

variable "git_commit" {
  type        = string
  default     = "unknown"
  description = "Commit the image was built from. Set by CI as PKR_VAR_git_commit; 'unknown' when built from a dirty tree."
}

// ---------------------------------------------------------------------------
// Installation source
// ---------------------------------------------------------------------------

variable "iso_url" {
  type        = string
  description = "ISO location. A local path is used as-is; a URL is downloaded into packer_cache. Ignored by azure-arm, which builds from a marketplace image."
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the installation ISO, as 'sha256:<hex>'. Never set this to 'none' — policy/packer.rego fails the build if you do."

  validation {
    condition     = can(regex("^(sha256|sha512):[0-9a-fA-F]+$", var.iso_checksum))
    error_message = "The iso_checksum must be an algorithm-prefixed hex digest such as sha256 followed by a colon and the digest, never none."
  }
}

variable "boot_command" {
  type        = list(string)
  description = "Keystrokes that put the installer into unattended mode. Distro- and bootloader-specific, so it lives with the OS variables rather than in the shared source block."
}

// Guest OS type identifiers. These are per-distribution and per-platform, and
// they are not cosmetic: VMware and vSphere use them to pick default virtual
// hardware, and a wrong value produces a VM that installs but behaves oddly
// later. Set in the OS variable file alongside the ISO it describes.
variable "vmware_guest_os_type" {
  type        = string
  description = "VMware Workstation guest OS identifier, e.g. rockylinux-64 or ubuntu-64."
}

variable "vsphere_guest_os_type" {
  type        = string
  description = "vSphere guest OS identifier, e.g. rockyLinux_64Guest or ubuntu64Guest."
}

variable "boot_wait" {
  type        = string
  default     = "5s"
  description = "Delay before boot_command is typed, to let the bootloader menu render."
}

// ---------------------------------------------------------------------------
// Guest sizing. Build-time only — these do not constrain the deployed VM.
// ---------------------------------------------------------------------------

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type        = number
  default     = 4096
  description = "MB. Anaconda needs ~2.5 GB to run a graphical-free install reliably."
}

variable "disk_size" {
  type        = number
  default     = 25600
  description = "MB. Must exceed the sum of the logical volumes in the kickstart; qcow2 and VMDK both allocate sparsely, so this costs nothing until used."
}

// ---------------------------------------------------------------------------
// Build credentials
//
// The build user is created by the installer with a public key injected at
// build time and no password. The matching private key is ephemeral — generated
// per build by scripts/make-build-key.sh, never committed, and the account
// itself is removed before the image is published (phase 2).
// ---------------------------------------------------------------------------

variable "build_username" {
  type    = string
  default = "packer"
}

variable "ssh_public_key" {
  type        = string
  description = "Public half of the ephemeral build key, injected into the image by the installer. Set via PKR_VAR_ssh_public_key."
  sensitive   = false

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.ssh_public_key))
    error_message = "The ssh_public_key must be an OpenSSH-format public key; run scripts/make-build-key.sh to generate one."
  }
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the private half of the ephemeral build key. Set via PKR_VAR_ssh_private_key_file."
}

variable "ssh_timeout" {
  type        = string
  default     = "45m"
  description = "Generous, because an unaccelerated CI build spends most of this on the installer rather than on SSH."
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

variable "output_directory" {
  type        = string
  default     = "builds"
  description = "Gitignored. Artefacts never enter the repository."
}

variable "headless" {
  type        = bool
  default     = true
  description = "Set false locally to watch the installer in a console window when a boot_command is misbehaving."
}

// ---------------------------------------------------------------------------
// vSphere — dummy defaults so `packer validate` covers this source without
// credentials. Real values come from PKR_VAR_* environment variables; see
// docs/VSPHERE-PATH.md. Never commit real values.
// ---------------------------------------------------------------------------

variable "vcenter_server" {
  type    = string
  default = "vcenter.invalid"
}

variable "vcenter_username" {
  type    = string
  default = "administrator@vsphere.local"
}

variable "vcenter_password" {
  type      = string
  default   = "dummy-not-a-real-password"
  sensitive = true
}

variable "vcenter_insecure" {
  type        = bool
  default     = true
  description = "True only because the nested lab uses VCSA's self-signed certificate. False against production."
}

variable "vsphere_datacenter" {
  type    = string
  default = "Datacenter"
}

variable "vsphere_cluster" {
  type    = string
  default = "Cluster"
}

variable "vsphere_datastore" {
  type    = string
  default = "datastore1"
}

variable "vsphere_folder" {
  type    = string
  default = "templates"
}

variable "vsphere_network" {
  type    = string
  default = "VM Network"
}

// ---------------------------------------------------------------------------
// Azure — likewise dummy defaults for validate. Authentication in CI is a
// GitHub OIDC federated credential: no client secret exists to leak.
// ---------------------------------------------------------------------------

variable "azure_subscription_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "azure_tenant_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "azure_client_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "azure_location" {
  type        = string
  default     = "uksouth"
  description = "One region only. Replication fan-out is the fastest way to spend real money in a gallery."
}

variable "azure_resource_group" {
  type    = string
  default = "rg-golden-image-factory"
}

variable "azure_gallery_name" {
  type    = string
  default = "goldenimagefactory"
}

// The OIDC token itself. With a GitHub federated credential there is no client
// secret to store — the workflow requests a short-lived token from the Actions
// runtime and passes it here as PKR_VAR_azure_oidc_token. The dummy default
// exists so `packer validate` can cover this source without credentials; the
// azure plugin authenticates during prepare, so leaving it unset makes the
// source unvalidatable. See ADR-0010.
variable "azure_oidc_token" {
  type      = string
  default   = "dummy-token-replaced-by-ci-at-runtime"
  sensitive = true
}

variable "azure_vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "Smallest size that builds in reasonable time. Cost per build is in docs/RUNBOOK.md."
}

// The azure-arm builder starts from a marketplace image, not an ISO. That is the
// correct Azure pattern and it means the Azure image shares this repo's Ansible
// roles and tests with the VMware images, but NOT their installer configuration.
// See docs/DECISIONS.md — do not imply the images are bit-identical.
variable "azure_base_publisher" {
  type    = string
  default = "resf"
}

variable "azure_base_offer" {
  type    = string
  default = "rockylinux-x86_64"
}

variable "azure_base_sku" {
  type    = string
  default = "9-base"
}
