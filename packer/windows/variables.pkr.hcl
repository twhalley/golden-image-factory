// ---------------------------------------------------------------------------
// Image identity
// ---------------------------------------------------------------------------

variable "os_name" {
  type    = string
  default = "windows2022"
}

variable "os_family" {
  type    = string
  default = "windows"
}

variable "image_version" {
  type    = string
  default = "0.1.0"
}

variable "git_commit" {
  type    = string
  default = "unknown"
}

// ---------------------------------------------------------------------------
// Installation source
//
// Microsoft does NOT publish a checksum alongside the evaluation ISO — unlike
// Rocky (published, though its minimal entry is wrong — ADR-0013) and Ubuntu
// (published and GPG-signed). The digest below was computed from a download
// whose size matched the Content-Length the server advertised, and is pinned so
// that a *different* file cannot be substituted silently on a later build.
//
// Being precise about what that does and does not buy, because it is the weakest
// link in this repo's supply chain: it detects change between builds. It does
// not establish that the original download was authentic, because there is no
// vendor-published digest to compare against. Recorded in THREATMODEL.md.
// ---------------------------------------------------------------------------

variable "iso_url" {
  type        = string
  default     = "https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
  description = "Windows Server 2022 evaluation media. 180-day evaluation; see docs/RUNBOOK.md for the licensing swap."
}

variable "iso_checksum" {
  type        = string
  default     = "sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
  description = "Observed digest, not a vendor-published one. See the note above and docs/THREATMODEL.md."
}

variable "windows_image_name" {
  type        = string
  default     = "Windows Server 2022 SERVERSTANDARDCORE"
  description = "WIM edition to install. Server Core by default; drop the CORE suffix for Desktop Experience."
}

// ---------------------------------------------------------------------------
// Guest sizing. Windows needs more than the Linux images for both install and
// the Windows Update run.
// ---------------------------------------------------------------------------

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type        = number
  default     = 4096
  description = "MB. Setup will run in less, but the Windows Update pass in the hardening role is slow below 4 GB."
}

variable "disk_size" {
  type        = number
  default     = 51200
  description = "MB. Server Core installs in roughly 10 GB; the headroom is for the update cache, reclaimed before publish."
}

// ---------------------------------------------------------------------------
// Build credentials
//
// Windows has no key-based equivalent to the ephemeral SSH key the Linux images
// use (ADR-0012), so a password is unavoidable. The mitigations are that it is
// generated per build by scripts/make-build-key.sh, exists only in the
// environment, is never written to the repository, and the account it belongs to
// is disabled by sysprep before the image is published. See ADR-0018.
// ---------------------------------------------------------------------------

variable "admin_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type        = string
  sensitive   = true
  description = "Per-build Administrator password. Set via PKR_VAR_winrm_password; never committed."

  validation {
    condition     = length(var.winrm_password) >= 14
    error_message = "The winrm_password must be at least 14 characters; run scripts/make-build-key.sh to generate one."
  }
}

variable "winrm_timeout" {
  type        = string
  default     = "2h"
  description = "Generous: Windows Setup plus first logon is slow, and slower still without KVM on a CI runner."
}

variable "computer_name" {
  type        = string
  default     = "WIN2022-GOLD"
  description = "Replaced by sysprep at deployment; only ever seen during the build."
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

variable "output_directory" {
  type    = string
  default = "builds"
}

variable "headless" {
  type    = bool
  default = true
}

// ---------------------------------------------------------------------------
// vSphere — dummy defaults so `packer validate` covers this source without
// credentials, exactly as the Linux templates do.
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
  type    = bool
  default = true
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
